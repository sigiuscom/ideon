import { readFileSync } from "node:fs";

const audit = JSON.parse(readFileSync(process.argv[2], "utf8"));
const allowed = new Set(["@boxyhq/saml-jackson", "node-forge"]);

const vulnerabilities = Object.entries(audit.vulnerabilities ?? {}).filter(
  ([name, vulnerability]) =>
    !allowed.has(name) &&
    ["high", "critical"].includes(vulnerability.severity),
);

if (vulnerabilities.length === 0) {
  console.log(
    "Only known unpatched node-forge audit entries remain via @boxyhq/saml-jackson.",
  );
  process.exit(0);
}

for (const [name, vulnerability] of vulnerabilities) {
  console.error(`${name}: ${vulnerability.severity} ${vulnerability.range}`);
}
process.exit(1);
