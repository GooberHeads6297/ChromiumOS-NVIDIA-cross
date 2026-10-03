// Open the local-account setup UI once per profile when the extension loads.
chrome.runtime.onInstalled.addListener(() => {
  chrome.tabs.create({ url: "http://127.0.0.1:17891/" }).catch(() => {
    // Login/OOBE may block tab create; popup still works.
  });
});
