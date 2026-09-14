const fs = require("fs");
const path = require("path");
const { jestConfig } = require("@salesforce/sfdx-lwc-jest/config");

const LABELS_FILE = path.join(
  __dirname,
  "force-app/main/default/labels/CustomLabels.labels-meta.xml"
);
const LABEL_MOCKS = path.join(__dirname, "jest-mocks/labels");

/**
 * sfdx-lwc-jest resolves every @salesforce/label import to its own name
 * ("c.Gx_Survey_Button_Next"). Tests should see the real wording instead, so
 * each label in the repo becomes a tiny module holding its value. Rebuilt on
 * every run from the labels file, so a changed label is never tested stale.
 */
function writeLabelMocks() {
  if (!fs.existsSync(LABELS_FILE)) {
    return;
  }
  const decode = (text) =>
    text
      .replace(/&lt;/g, "<")
      .replace(/&gt;/g, ">")
      .replace(/&quot;/g, '"')
      .replace(/&apos;/g, "'")
      .replace(/&amp;/g, "&");
  fs.mkdirSync(LABEL_MOCKS, { recursive: true });
  const xml = fs.readFileSync(LABELS_FILE, "utf8");
  for (const block of xml.match(/<labels\s*>[\s\S]*?<\/labels\s*>/g) || []) {
    const name = /<fullName\s*>([\s\S]*?)<\/fullName\s*>/.exec(block);
    const value = /<value\s*>([\s\S]*?)<\/value\s*>/.exec(block);
    if (name && value) {
      fs.writeFileSync(
        path.join(LABEL_MOCKS, `${name[1].trim()}.js`),
        `export default ${JSON.stringify(decode(value[1]))};\n`
      );
    }
  }
}
writeLabelMocks();

module.exports = {
  ...jestConfig,
  moduleNameMapper: {
    ...(jestConfig.moduleNameMapper || {}),
    // sfdx-lwc-jest ships no stub for lightning/modal
    "^lightning/modal$": "<rootDir>/jest-mocks/lightning/modal",
    // Real label values, generated above
    "^@salesforce/label/c\\.(.+)$": "<rootDir>/jest-mocks/labels/$1"
  },
  modulePathIgnorePatterns: ["<rootDir>/.localdevserver"]
};
