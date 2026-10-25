.pragma library
// Shared between anshu.bar and anshu.menu (same shell process, one instance per
// engine): the menu reaches the live bar through this to make the island
// itself become the menu card — hide it the frame the morph starts, read its
// exact geometry and palette, and hand it back when the card is home.
var bar = null
