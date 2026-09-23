async function load(name) {
  const helper = require(name);
  return helper("bob");
}
load("./helper3.cjs").then(function(result) {
  console.log(result);
});
