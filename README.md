# EcoFlow Dashboard

A small web dashboard for EcoFlow power stations and the power outage schedule

## Setup

```bash
bundle install
cp .env.example .env    # fill in the EcoFlow keys, OUTAGE_GROUP + OBLENERGO, WEATHER_LAT/LON
bundle exec bin/server  # http://localhost:4567
```

## Docker (locally)

```bash
docker compose up --build   # http://localhost:4567, data kept in ./data
```

## Deploy to Render

1. Commit the lockfile for Linux too, and push the repo to GitHub:
   ```bash
   bundle lock --add-platform x86_64-linux
   git add . && git commit -m "Deploy to Render" && git push
   ```
   Check that `.env` is **not** in the commit (`git status`): it's in `.gitignore`.
2. Render Dashboard → **New → Blueprint** → choose the repo. Render reads `render.yaml`.
3. Render asks for the `sync: false` values: `ECOFLOW_ACCESS_KEY`, `ECOFLOW_SECRET_KEY`,
   `ECOFLOW_SN`, `OUTAGE_GROUP` + `OBLENERGO`, `WEATHER_LAT` + `WEATHER_LON`.
   Location values have no defaults in the code: leave a pair empty to turn that feature off.
   Enter them and click **Apply**.
4. Open `https://ecoflow-dashboard.onrender.com`.

## Tests

```bash
bundle exec rake
```

```bash
wc -l data/samples/$(date +%F).jsonl
tail -2 data/samples/$(date +%F).jsonl
```
