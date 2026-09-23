const name = "./helper.cjs";
delete require.cache[require.resolve(name)];
const first = require(name);
delete require.cache[require.resolve(name)];
const second = require(name);
console.log(first());
console.log(second());
console.log(first !== second);
