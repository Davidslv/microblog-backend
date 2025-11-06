# Running Solid Queue in Development

## Problem
On macOS, running Solid Queue inside Puma (via the Puma plugin) causes fork() crashes due to Objective-C runtime issues.

## Solution
Run Solid Queue in a separate process instead of inside Puma.

## Setup

### Option 1: Using bin/jobs (Recommended for Development)

1. Start the Rails server (without Solid Queue in Puma):
   ```bash
   DISABLE_RACK_ATTACK=true bin/rails server -p 3000
   ```

2. In a separate terminal, start Solid Queue workers:
   ```bash
   SOLID_QUEUE_WORKER=true bin/jobs
   ```

### Option 2: Using Procfile.dev (Foreman)

If you have Foreman installed, you can use the Procfile.dev:

```bash
foreman start -f Procfile.dev
```

This will start both the Rails server and Solid Queue workers.

### Option 3: Using SOLID_QUEUE_IN_PUMA (Production/Simple Deployments)

For production or when you don't need separate processes:

```bash
SOLID_QUEUE_IN_PUMA=true DISABLE_RACK_ATTACK=true bin/rails server -p 3000
```

**Note:** This will crash on macOS due to fork() issues, but works fine on Linux.

## Configuration

- `config/environments/development.rb`: Always uses `:solid_queue` adapter
- `config/puma.rb`: Only loads Solid Queue plugin when `SOLID_QUEUE_IN_PUMA=true`
- `bin/jobs`: Runs Solid Queue workers in a separate process

## Background Jobs

Background jobs (like `BackfillFeedJob`) will be queued and processed by the Solid Queue worker process.

## Monitoring

You can monitor jobs at: http://localhost:3000/mission_control/jobs
- Username: `admin`
- Password: `admin` (development only)

