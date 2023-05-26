// Array difference a - b 
function difference(a, b) {
  return a.filter((x) => !b.some((y) => x == y));
};
