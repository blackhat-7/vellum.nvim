// npm ci must not download a browser: the headless shell is a ~100 MB
// download that :Vellum build installs explicitly when diagrams are on.
module.exports = { chrome: { skipDownload: true }, 'chrome-headless-shell': { skipDownload: true } };
