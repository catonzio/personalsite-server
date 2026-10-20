// Edit this file to add/remove services. Changes are live on reload.
// lan: true  -> URL built from LAN_HOST, works only from home LAN or VPN.
// lan: false -> path served by Traefik on the public domain.
const LAN_HOST = "192.168.1.101";

const GROUPS = [
  {
    title: "Infrastructure",
    note: "Home LAN or VPN only",
    services: [
      { name: "wg-easy", desc: "WireGuard VPN clients", lan: true, scheme: "http", port: 51821, path: "/" },
      { name: "Portainer", desc: "Docker containers", lan: true, scheme: "https", port: 9443, path: "/" },
      { name: "Pi-hole", desc: "DNS and ad blocking", lan: true, scheme: "http", port: 8080, path: "/admin/" },
      { name: "Traefik", desc: "Routers and services", lan: true, scheme: "http", port: 8081, path: "/dashboard/" },
    ],
  },
  {
    title: "Apps",
    note: "Public, via Traefik",
    services: [
      { name: "Portfolio", desc: "Personal site", path: "/portfolio/" },
      { name: "DLS platform", desc: "Production", path: "/dls-platform/" },
      { name: "DLS platform staging", desc: "Staging (basic auth)", path: "/dls-platform-staging/" },
      { name: "Privacy policy", desc: "Policies", path: "/privacy-policy/" },
      { name: "Prova", desc: "Demo template", path: "/prova/" },
    ],
  },
];
