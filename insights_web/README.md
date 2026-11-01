# InstaPulse – Instagram analytics + Claude

Single-file web app (`index.html`): Instagram evolution dashboard (followers, reach, impressions, engagement, profile views), content-type and best-day charts, sortable posts table, CSV/JSON import & export, and a Claude chat panel that answers questions using the dashboard data.

## Run
```bash
cd insights_web && python3 -m http.server 8080
```
Open http://localhost:8080, click **⚙ Claude key**, paste your Anthropic API key.

## Your data
Starts with demo data. Import a CSV with columns `date,followers,reach,impressions,engagement,profileViews` (daily) or `date,type,caption,reach,likes,comments,saves,shares` (posts), or a JSON `{ "daily": [...], "posts": [...] }`.
