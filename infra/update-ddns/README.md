# Update DDNS

This is a little project that helps updating the DNS entries of a IONOS domain when the IP is dynamic.

## Installation

1. Install [uv](https://docs.astral.sh/uv/)
2. Get the API key following the [guide](https://developer.hosting.ionos.it/docs/getstarted)
3. Set up the `.env` file:
    1. Copy the file: `cp .env.sample .env`
    2. Update the fields `IONOS_PRIVATE_APIKEY` and `IONOS_PUBLIC_APIKEY` of the `.env` file with your keys
    3. Update the field `DOMAINS` with your domains
4. Follow configuration of official projects: [project](https://www.ionos.it/aiuto/domini/configurare-un-indirizzo-ip/connettere-un-dominio-a-una-rete-con-ip-variabile-utilizzando-il-dns-dinamico-linux/)

## Usage

In order to use the program, you should:

1. Install dependencies with uv: `uv sync`
2. Execute the program with the project script: `uv run update-ddns`
3. Alternative execution via module: `uv run python -m update_ddns`

## References

- [IONOS API DNS Documentation](https://developer.hosting.ionos.it/docs/dns)

## Authors

- Danilo Catone [danilocatone@gmail.com](https://danilocatone.com)
