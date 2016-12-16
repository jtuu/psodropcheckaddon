//does not work because rares.json has typos -_-
const fs = require("fs")

const rares = require("./rares.json").map(r => r.trim()).reduce((p, c) => (p[c.toLowerCase()] = true, p), {})
const items = fs.readFileSync("./items.txt", "utf8").split("\n").map(r => r.split(","))
items.forEach(i => i.shift())
items.pop()

for(let i = 0; i < items.length; i++){
	if(items[i][1].toLowerCase() in rares){
		items[i].push("*")
	}
	console.log(items[i].join(" "))
}

