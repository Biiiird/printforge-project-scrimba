import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Lets deploys build into a staging dir (NEXT_DIST_DIR=.next-staging) while
  // the live version keeps serving, so a failed build never causes an outage.
  distDir: process.env.NEXT_DIST_DIR || ".next",
};

export default nextConfig;
