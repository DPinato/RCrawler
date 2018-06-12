# RCrawler
## Measure network performance over time

RCrawler allows monitoring PING and HTTP GET performance of destinations specified in a config file. Each specified operation can be configured to run at a specific interval and number of time. Through a multi-threading approach, the destinations are monitored simultaneously and email alerts are sent for destinations that are unresponsive for a configurable consecutive number of attempts.

The Logger Ruby gem is used to provide logs of RCrawler's operations.

Clone this repository and start RCrawler with:
```
https://github.com/DPinato/RCrawler.git
cd RCrawler
./RCrawler.rb <config_file>
```

RCrawler can run in an instanced mode using the optional -i flag, which allows feeding the same config file to multiple RCrawler processes. Each instance will execute a number of operations equivalent to *operationsPerInstance*, from the config file.


Things TODO:
- Add support for sending alerts to multiple email addresses
- Plot data collected
	- Provide front-end where data collected is shown
- Add options in config file for:
	- Number of old logs to keep
	- Maximum log file size
	-	Logging level (Logger.level)
