## v1.2

### Added

- Loop control of retrieving of local components
  - if status is `error` and `complete` exit
  - if status is `on-progress` continue the loop

## v1.1

### Change

- Place auto scan network function inside the `connect` option

### Fix

- Continous looping and exit inside the main menu

## v1.0

### Added

- Auto reconnect after rescanning cache

### Fix

- Getting local components printer - add `network` property in filtering

## v0.2p

### Added

- Auto scan when cache expire

### Fix

- Program closes after mapping a new hard drive
