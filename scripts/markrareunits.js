const fs = require("fs")

const nonrares = require("./nonrareunits.json").map(r => r.trim()).reduce((p, c) => (p[c.toLowerCase()] = true, p), {})
const units = fs.readFileSync("./units", "utf8").split("\n").map(r => r.split(","))
units.pop()

for(let i = 0; i < units.length; i++){
	if(units[i][1].toLowerCase() in nonrares){
		units[i].push("0")
	}else{
		units[i].push("1")
	}
	console.log(units[i].join(","))
}

