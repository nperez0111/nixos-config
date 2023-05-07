Store secrets with [agenix](https://github.com/ryantm/agenix)

Create a new secret:
```sh
nix run github:ryantm/agenix -- -e newsecret
```

Edit an existing secret:
```sh
nix run github:ryantm/agenix -- -e github
```