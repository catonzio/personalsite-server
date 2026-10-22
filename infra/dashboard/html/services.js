// Infrastructure services not routed by Traefik: edit by hand.
// Apps are discovered automatically from the Traefik API (see index.html).
// URLs are built from LAN_HOST and work only from home LAN or VPN.
const LAN_HOST = "192.168.1.101";

const INFRA = [
  { name: "wg-easy", desc: "WireGuard VPN clients", scheme: "http", port: 51821, path: "/" },
  { name: "Portainer", desc: "Docker containers", scheme: "https", port: 9443, path: "/" },
  { name: "Pi-hole", desc: "DNS and ad blocking", scheme: "http", port: 8080, path: "/admin/" },
  { name: "Traefik", desc: "Routers and services", scheme: "http", port: 8081, path: "/dashboard/" },
];

// Monitor tab: default live refresh (seconds) and history range. Both can be
// changed in the page (remembered per browser) or via URL, e.g. ?refresh=10&range=7d
const MONITOR_DEFAULTS = { refresh: 5, range: "24h" };

// Top-level paths never shown as apps.
const HIDDEN_PATHS = ["api", "infra", "dashboard"];
