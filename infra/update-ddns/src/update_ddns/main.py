import json
import os

import dotenv
import requests

SERVER_URL: str = "https://api.hosting.ionos.com/dns"
DDNS_URL: str = f"{SERVER_URL}/v1/dyndns"


class EnvSettings:
    api_key: str
    domains: list[str]

    def __init__(self, api_key: str, domains: list) -> None:
        self.api_key = api_key
        self.domains = domains


def build_headers(api_key: str) -> dict[str, str]:
    return {"Content-Type": "application/json", "X-API-Key": api_key}


def build_body(domains: list[str]) -> dict[str, list | str]:
    return {"domains": domains, "description": "DynamicDNS"}


def load_env_settings() -> EnvSettings:
    dotenv.load_dotenv()
    public: str = os.getenv("IONOS_PUBLIC_APIKEY", "")
    secret: str = os.getenv("IONOS_PRIVATE_APIKEY", "")
    domains: list = json.loads(os.getenv("DOMAINS", "[]"))
    return EnvSettings(api_key=f"{public}.{secret}", domains=domains)


def get_update_url(api_key: str, domains: list[str]) -> str:
    url: str = DDNS_URL
    headers = build_headers(api_key)
    body = build_body(domains)

    response = requests.post(url, headers=headers, json=body)
    if response.status_code == 200:
        resp_body = response.json()
        return resp_body["updateUrl"]
    else:
        raise Exception(
            f"Response returned with status code {response.status_code} while retrieving update URL"
        )


def make_update(update_url: str) -> bool:
    response = requests.get(update_url)
    return response.status_code == 200


def main():
    print("Loading API key... ", end="", flush=True)
    env_settings: EnvSettings = load_env_settings()
    print("Done!")

    print("Fetching update url... ", end="", flush=True)
    update_url: str = get_update_url(env_settings.api_key, env_settings.domains)
    print("Done!")

    print("Updating DNS entry... ", end="", flush=True)
    result: bool = make_update(update_url)
    if result:
        print("Done!")
    else:
        print("Error!")


if __name__ == "__main__":
    main()
