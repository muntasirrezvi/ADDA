import path from "node:path";
import { fileURLToPath } from "node:url";
const dir = path.dirname(fileURLToPath(import.meta.url));

/** Static site: deploy the "out" folder anywhere (Vercel, Netlify, Cloudflare Pages). */
export default {
  output: "export",
  // set when the console is served from a sub-folder, e.g. GitHub Pages at /ADDA
  basePath: process.env.NEXT_BASE_PATH || "",
  images: { unoptimized: true },
  trailingSlash: true,
  outputFileTracingRoot: dir,
  webpack: (config) => {
    config.resolve.alias["@"] = dir;
    return config;
  },
};
