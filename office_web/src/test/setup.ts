import '@testing-library/jest-dom/vitest';

// jsdom doesn't implement scrollIntoView at all -- this is the standard shim.
if (typeof Element !== 'undefined' && !Element.prototype.scrollIntoView) {
  Element.prototype.scrollIntoView = () => {};
}
