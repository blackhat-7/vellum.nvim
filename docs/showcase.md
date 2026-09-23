# Checkout Platform — Design Notes

[![build](https://img.shields.io/badge/build-passing-2ea44f.svg)](#) [![coverage](https://img.shields.io/badge/coverage-94%25-8957e5.svg)](#) [![slo](https://img.shields.io/badge/p99-180ms-blue.svg)](#)

How an order moves from a phone to a warehouse: the **services**, the *saga* that
keeps them consistent, and the ~~two-phase commit~~ we replaced. Owners: `@payments`,
`@fulfilment`. See the [runbook](#) for incidents[^oncall].

> [!NOTE]
> Every service runs in **two availability zones**. Losing one zone costs capacity,
> never correctness.

## 1. Architecture

Traffic enters at the edge, passes the Istio gateway, and fans out to three
services per zone. Writes leave through Kafka; reads hit Redis first.

```mermaid
graph TB
    %% Core Styling Definitions
    classDef edgeNode fill:#1E293B,stroke:#38BDF8,stroke-width:2px,color:#FFF;
    classDef k8sService fill:#0F172A,stroke:#10B981,stroke-width:2px,color:#FFF;
    classDef dbNode fill:#311005,stroke:#EF4444,stroke-width:2px,color:#FFF;
    classDef queueNode fill:#1E1B4B,stroke:#F59E0B,stroke-width:2px,color:#FFF;
    
    %% External Traffic & Edge Layer
    subgraph Edge_Layer ["🌐 Global Edge Layer"]
        DNS[Anycast DNS / Cloudflare] --> WAF[Web Application Firewall]
        WAF --> CDN[Global CDN Cache]
        WAF --> ALB[Layer 7 Application Load Balancer]
    end

    %% Kubernetes Cluster Environment
    subgraph EKS_Cluster ["📦 Kubernetes Production Cluster (EKS)"]
        
        subgraph AZ1 ["Availability Zone A"]
            direction TB
            subgraph Pods_AZ1 ["Replicas A"]
                Auth_SVC_A["🔐 Auth Service (Go)"]
                Order_SVC_A["🛒 Order Service (Java)"]
                User_SVC_A["👥 User Service (Node.js)"]
            end
        end

        subgraph AZ2 ["Availability Zone B"]
            direction TB
            subgraph Pods_AZ2 ["Replicas B"]
                Auth_SVC_B["🔐 Auth Service (Go)"]
                Order_SVC_B["🛒 Order Service (Java)"]
                User_SVC_B["👥 User Service (Node.js)"]
            end
        end
        
        %% Service Mesh Inter-communication
        Ingress_Controller["🕸️ Istio Ingress Gateway"]
    end

    %% Event Mesh & Message Broker
    subgraph Event_Mesh ["⚡ Event-Driven Message Streaming Pipeline"]
        direction LR
        Kafka_Broker_1[(Kafka Broker 1)]
        Kafka_Broker_2[(Kafka Broker 2)]
        Kafka_Broker_3[(Kafka Broker 3)]
        
        Kafka_Broker_1 <--> Zookeeper{Zookeeper Quorum}
        Kafka_Broker_2 <--> Zookeeper
        Kafka_Broker_3 <--> Zookeeper
    end

    %% Storage & Persistence Tier
    subgraph Storage_Tier ["💾 Polyglot Persistence Layer"]
        subgraph Relational_DB ["Aurora PostgreSQL (ACID Data)"]
            Postgres_Writer[(Primary Writer)]
            Postgres_Reader[(Read Replica)]
            Postgres_Writer -- Synchronous Replication --> Postgres_Reader
        end
        
        subgraph Cache_Cluster ["Redis Cluster (Session & Cache)"]
            Redis_Leader[(Redis Leader)]
            Redis_Follower[(Redis Follower)]
            Redis_Leader -- Async Replication --> Redis_Follower
        end
        
        subgraph NoSQL_Store ["DynamoDB (Audit Logs)"]
            DDB[(DynamoDB Tables)]
        end
    end

    %% Edge Traffic Routing
    ALB --> Ingress_Controller
    
    %% Ingress to Mesh routing
    Ingress_Controller --> Auth_SVC_A & Auth_SVC_B
    Ingress_Controller --> Order_SVC_A & Order_SVC_B
    Ingress_Controller --> User_SVC_A & User_SVC_B

    %% Cross-service RPC Communications
    Order_SVC_A -- gRPC Auth Check --> Auth_SVC_A
    Order_SVC_B -- gRPC Auth Check --> Auth_SVC_B
    Order_SVC_A -- Fetch Profile Info --> User_SVC_A
    Order_SVC_B -- Fetch Profile Info --> User_SVC_B

    %% Event Publishing
    Order_SVC_A & Order_SVC_B -- "Publish 'OrderCreated'" --> Kafka_Broker_1
    User_SVC_A & User_SVC_B -- "Publish 'UserRegistered'" --> Kafka_Broker_2

    %% Storage Interfacing
    Auth_SVC_A & Auth_SVC_B ----> Redis_Leader
    User_SVC_A & User_SVC_B ----> Postgres_Writer
    Order_SVC_A & Order_SVC_B ----> DDB
    
    %% Apply Visual Classes
    class DNS,WAF,CDN,ALB edgeNode;
    class Ingress_Controller,Auth_SVC_A,Auth_SVC_B,Order_SVC_A,Order_SVC_B,User_SVC_A,User_SVC_B k8sService;
    class Postgres_Writer,Postgres_Reader,Redis_Leader,Redis_Follower,DDB dbNode;
    class Kafka_Broker_1,Kafka_Broker_2,Kafka_Broker_3,Zookeeper queueNode;
```

| Tier      | Tech               | Replicas | p99 budget | Owner        |
| :-------- | :----------------- | -------: | ---------: | :----------- |
| Edge      | Cloudflare, ALB    |        — |      12 ms | `@platform`  |
| Services  | Go, Java, Node.js  |        6 |      90 ms | `@checkout`  |
| Streaming | Kafka ×3           |        3 |      25 ms | `@data`      |
| Storage   | Aurora, Redis, DDB |        5 |      40 ms | `@storage`   |

## 2. Capacity model

Each service is an $M/M/c$ queue. With arrival rate $\lambda$ and service rate
$\mu$ per pod, utilisation is $\rho = \lambda / (c\mu)$ and must stay below $0.7$.
Little's law, $L = \lambda W$, turns the latency budget into a queue-depth alarm.

$$
W = \frac{1}{\mu} + \frac{C(c, \lambda/\mu)}{c\mu - \lambda},
\qquad
C(c, a) = \frac{\dfrac{a^c}{c!}\,\dfrac{c}{c - a}}{\displaystyle\sum_{k=0}^{c-1} \frac{a^k}{k!} + \frac{a^c}{c!}\,\frac{c}{c - a}}
$$

Two zones with availability $a_i$ fail only together:

```math
\begin{aligned}
A_{\text{region}} &= 1 - \prod_{i=1}^{2} \left(1 - a_i\right) \\
                  &= 1 - (1 - 0.999)^2 = 0.999999
\end{aligned}
```

Retries back off exponentially with full jitter, where $n$ is the attempt:

$$
d_n \sim \mathcal{U}\!\left(0,\; \min\left(d_{\max},\, d_0 \cdot 2^{n}\right)\right),
\qquad
\mathbb{E}[d_n] = \tfrac{1}{2}\min\left(d_{\max},\, d_0 2^{n}\right)
$$

## 3. Checkout saga

No distributed lock, no two-phase commit. The orchestrator runs local steps and
undoes finished ones with **compensations** when a later step fails.

```mermaid
sequenceDiagram
    autonumber
    actor Client as 📱 Mobile Client
    participant API as 🚪 API Gateway
    participant Saga as 🧠 Saga Orchestrator
    participant Inventory as 📦 Inventory Service
    participant Payment as 💳 Payment Gateway
    participant Delivery as 🚚 Delivery Service

    Client->>API: POST /api/v2/orders (Payload)
    activate API
    API->>Saga: InitializeTransaction(OrderPayload)
    activate Saga
    Saga-->>API: 202 Accepted (Tracking ID)
    API-->>Client: 202 Accepted (Tracking ID)
    deactivate API

    Note over Saga, Delivery: Phase 1: Local Transaction Reservations

    Saga->>Inventory: ReserveStock(ItemsList, OrderID)
    activate Inventory
    alt Stock Available
        Inventory-->>Saga: StockReserved (Success)
    else Out of Stock
        Inventory-->>Saga: StockReservationFailed (Error)
        Note over Saga: Trigger Compulsory Abortion
        Saga->>Client: Push Notification: Order Failed (Out of Stock)
    end
    deactivate Inventory

    Saga->>Payment: AuthorizeFunds(CardToken, Amount)
    activate Payment
    alt Payment Authorized Successfully
        Payment-->>Saga: FundsAuthorized (Capture Token)
    else Insufficient Funds / Auth Denied
        Payment-->>Saga: AuthorizationFailed (Declined)
        activate Inventory
        Note over Saga, Inventory: Compensation Phase Initiated
        Saga->>Inventory: ReleaseStockCompensation(ItemsList, OrderID)
        Inventory-->>Saga: StockReleasedAck
        deactivate Inventory
        Saga->>Client: Push Notification: Payment Failed
    end
    deactivate Payment

    Note over Saga, Delivery: Phase 2: Finalization & Logistics Hand-off

    Saga->>Delivery: CreateShipmentManifest(UserAddress, OrderID)
    activate Delivery
    alt Logistics Success
        Delivery-->>Saga: ManifestCreated (TrackingNumber)
        Saga->>Payment: ConfirmCapture(CaptureToken)
        Payment-->>Saga: FundsSettled
        Saga->>Client: Dispatch SSE Event: OrderCompleted 🎉
    else Logistics Partner API Timeout
        Delivery-->>Saga: DispatchRegistrationFailed
        
        Note over Saga, Payment: Cascade Rollback Executing
        Saga->>Payment: ReverseAuthorization(CaptureToken)
        Payment-->>Saga: AuthorizationVoided
        
        Saga->>Inventory: ReleaseStockCompensation(ItemsList, OrderID)
        Inventory-->>Saga: StockReleasedAck
        
        Saga->>Client: Push Notification: Logistics Error (Refunded)
    end
    deactivate Delivery
    deactivate Saga
```

> [!WARNING]
> Compensations must be **idempotent**. The orchestrator retries them after a crash,
> so `ReleaseStock` may run twice for one order.

Step failure rates compound. With per-step failure $p_k$:

$$
P(\text{rollback}) = 1 - \prod_{k=1}^{3} (1 - p_k) \approx \sum_{k=1}^{3} p_k
\quad \text{when } p_k \ll 1
$$

```go
func (s *Saga) Run(ctx context.Context, o Order) error {
	for i, step := range s.steps {
		if err := step.Do(ctx, o); err != nil {
			for j := i - 1; j >= 0; j-- {
				s.steps[j].Undo(ctx, o) // idempotent, retried on crash
			}
			return fmt.Errorf("step %s: %w", step.Name, err)
		}
	}
	return nil
}
```

## 4. Order state machine

```mermaid
stateDiagram-v2
    [*] --> PENDING_VALIDATION : Order Payload Created

    state PENDING_VALIDATION {
        [*] --> CheckSchema
        CheckSchema --> CheckFraud : Valid Schema
        CheckFraud --> FraudScoreApproved : Risk Score < Threshold
        CheckFraud --> FraudFlagged : Risk Score >= Threshold
    }

    PENDING_VALIDATION --> FAILED_FRAUD_CHECK : FraudFlagged
    PENDING_VALIDATION --> STOCK_RESERVATION_PHASE : FraudScoreApproved

    state STOCK_RESERVATION_PHASE {
        [*] --> QueryWarehouse
        QueryWarehouse --> AllocateInventory : In Stock
        AllocateInventory --> InventoryLocked : TTL 15 Mins
    }

    STOCK_RESERVATION_PHASE --> PAYMENT_PROCESSING : InventoryLocked
    STOCK_RESERVATION_PHASE --> OUT_OF_STOCK_CANCELLED : Stock Unavailable

    state PAYMENT_PROCESSING {
        [*] --> TokenizePayment
        TokenizePayment --> ExecuteGatewayCharge
        ExecuteGatewayCharge --> ChargeSuccessful : HTTP 200 OK
        ExecuteGatewayCharge --> ChargeFailed : HTTP 4xx/5xx
    }

    PAYMENT_PROCESSING --> ORDER_FULFILLED : ChargeSuccessful
    PAYMENT_PROCESSING --> PAYMENT_RETRY_LOOP : ChargeFailed

    state PAYMENT_RETRY_LOOP {
        💥 --> AttemptRetry : Retry Count < 3
        AttemptRetry --> ExecuteGatewayCharge
        💥 --> MaxRetriesExceeded : Retry Count >= 3
    }
    
    PAYMENT_RETRY_LOOP --> ORDER_EXPIRED_CANCELLED : MaxRetriesExceeded

    state ORDER_FULFILLED {
        [*] --> GenerateInvoice
        GenerateInvoice --> PushToLogisticsQueue
        PushToLogisticsQueue --> AwaitingCourierPickup
    }

    ORDER_FULFILLED --> [*] : Delivered to End User
    FAILED_FRAUD_CHECK --> [*]
    OUT_OF_STOCK_CANCELLED --> [*]
    ORDER_EXPIRED_CANCELLED --> [*]
```

The retry loop is bounded. An order leaves `PAYMENT_RETRY_LOOP` after at most
three attempts, so every path reaches a terminal state:

$$
T_{\text{worst}} = \sum_{n=0}^{2} d_n + 3\,t_{\text{charge}} \le 3\,(d_{\max} + t_{\text{charge}})
$$

## Rollout

1. Shadow traffic
   - mirror 1% of checkouts to the saga path
   - compare outcomes with the old flow
2. Canary in **zone A**, then zone B
3. Remove the two-phase commit code

- [x] Saga orchestrator
- [x] Idempotent compensations
- [ ] Chaos test: kill a zone mid-checkout
- [ ] Remove `legacy-2pc`

> [!IMPORTANT]
> Freeze deploys during the canary. A rollback must not race a schema migration.

<details>
<summary>Why not two-phase commit?</summary>

2PC holds locks across services while the coordinator waits. One slow payment
gateway would stall inventory for every order. The saga trades that for eventual
consistency, bounded by the retry budget above.

</details>

---

[^oncall]: Pager rotation: `@checkout-oncall`, 24/7.
