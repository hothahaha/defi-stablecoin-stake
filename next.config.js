/** @type {import('next').NextConfig} */
const nextConfig = {
    async redirects() {
        return [
            {
                source: "/",
                destination: "/markets",
                permanent: true,
            },
        ];
    },
};

module.exports = nextConfig;
