const fs = require("fs")

const nonrares = require("./nonrareweapons.json").map(r => r.trim()).reduce((p, c) => (p[c.toLowerCase()] = true, p), {})
const weapons = fs.readFileSync("./weapons", "utf8").split("\n").map(r => r.split(","))
weapons.pop()

for(let i = 0; i < weapons.length; i++){
	if(weapons[i][1].toLowerCase() in nonrares){
		weapons[i].push("0")
	}else{
		weapons[i].push("1")
	}
	console.log(weapons[i].join(","))
}

