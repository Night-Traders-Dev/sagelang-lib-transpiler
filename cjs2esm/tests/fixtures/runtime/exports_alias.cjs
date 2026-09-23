const exp = module.exports;
exp.run = function() {
  return "running";
};
exports.version = "1.0.0";
module.exports = function main() {
  return "main module";
};
console.log(module.exports());
console.log(typeof exp.run);
