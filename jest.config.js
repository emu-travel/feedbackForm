const { jestConfig } = require("@salesforce/sfdx-lwc-jest/config");

module.exports = {
  ...jestConfig,
  moduleNameMapper: {
    ...(jestConfig.moduleNameMapper || {}),
    // sfdx-lwc-jest ships no stub for lightning/modal
    "^lightning/modal$": "<rootDir>/jest-mocks/lightning/modal"
  },
  modulePathIgnorePatterns: ["<rootDir>/.localdevserver"]
};
