const fs = require("fs")

const nonrares = require("./nonrarearmors.json").map(r => r.trim()).reduce((p, c) => (p[c.toLowerCase()] = true, p), {})
const armors = fs.readFileSync("./armors", "utf8").split("\n").map(r => r.split(","))
armors.pop()

for(let i = 0; i < armors.length; i++){
	if(armors[i][1].toLowerCase() in nonrares){
		armors[i].push("0")
	}else{
		armors[i].push("1")
	}
	console.log(armors[i].join(","))
}

