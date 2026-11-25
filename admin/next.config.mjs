import path from "node:path";
import { fileURLToPath } from "node:url";
const dir = path.dirname(fileURLToPath(import.meta.url));

/** Static site: deploy the "out" folder anywhere (Vercel, Netlify, Cloudflare Pages). */
export default {
  output: "export",
  images: { unoptimized: true },
  trailingSlash: true,
  outputFileTracingRoot: dir,
  webpack: (config) => {
    config.resolve.alias["@"] = dir;
    return config;
  },
};
