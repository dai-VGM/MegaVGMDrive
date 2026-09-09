// Test-only dependencies are installed in a temporary directory via NODE_PATH.
const { JSDOM } = require("jsdom");
const dom = new JSDOM("<!doctype html><html><body></body></html>", {
  url: "http://fixture:8182", pretendToBeVisual: true,
});
for (const key of ["window", "document", "localStorage", "HTMLElement", "Node", "DocumentFragment", "MutationObserver"]) {
  globalThis[key] = dom.window[key];
}
globalThis.getComputedStyle = dom.window.getComputedStyle.bind(dom.window);
dom.window.scrollTo = ({ top }) => {
  Object.defineProperty(dom.window, "scrollY", { value: top, configurable: true });
};
Object.defineProperty(globalThis, "navigator", { value: dom.window.navigator, configurable: true });
globalThis.IS_REACT_ACT_ENVIRONMENT = true;
globalThis.testClock = require("@sinonjs/fake-timers").install({
  now: 1000, toFake: ["setTimeout", "clearTimeout", "setInterval", "clearInterval", "Date", "performance"],
});
for (const key of ["setTimeout", "clearTimeout", "setInterval", "clearInterval"]) window[key] = globalThis[key];
require(require("node:path").resolve(process.argv[2])).main().then(() => {
  testClock.uninstall(); dom.window.close();
  console.log("React DOM lifecycle tests: ALL PASS"); process.exit(0);
}, error => {
  console.error(error); testClock.uninstall(); dom.window.close(); process.exit(1);
});
