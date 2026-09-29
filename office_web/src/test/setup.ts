import '@testing-library/jest-dom/vitest';

// jsdom doesn't implement scrollIntoView at all -- this is the standard shim.
if (typeof Element !== 'undefined' && !Element.prototype.scrollIntoView) {
  Element.prototype.scrollIntoView = () => {};
}

// jsdom doesn't implement the Pointer Capture API either -- needed by any
// draggable handle (e.g. the resizable order-detail panel).
if (typeof Element !== 'undefined' && !Element.prototype.setPointerCapture) {
  Element.prototype.setPointerCapture = () => {};
  Element.prototype.releasePointerCapture = () => {};
  Element.prototype.hasPointerCapture = () => false;
}
