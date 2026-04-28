import fs from "node:fs";
import path from "node:path";

export const dirname = (filePath) => path.dirname(filePath);

export const ensureDirectory = (directoryPath) => () => {
  fs.mkdirSync(directoryPath, { recursive: true });
};

export const writeTextFile = (filePath) => (content) => () => {
  fs.writeFileSync(filePath, content, "utf8");
};
