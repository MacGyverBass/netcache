# Highlight the IP address
/^queries: /{
	$0=gensub(/ (([0-9]{1,3}\.){3}[0-9]{1,3})#/, " \e[95m\\1\e[0m#", "");
}

# Highlight the IP addresses
/^sniproxy: /{
	$0=gensub(/ (([0-9]{1,3}\.){3}[0-9]{1,3}):([0-9]*) -> (([0-9]{1,3}\.){3}[0-9]{1,3}):([0-9]*) -> (([0-9]{1,3}\.){3}[0-9]{1,3}):([0-9]*) /, " \e[95m\\1\e[0m:\\3 -> \\4:\\6 -> \e[96m\\7\e[0m:\\9 ", "");
}

# Highlight the IP addresses and HIT/MISS values
/^cache: /{
	$0=gensub(/ (([0-9]{1,3}\.){3}[0-9]{1,3}) /, " \e[95m\\1\e[0m ", "g");
	$0=gensub(/"HIT"/, "\"\e[92mHIT\e[0m\"", "");
	$0=gensub(/"MISS"/, "\"\e[93mMISS\e[0m\"", "");
}

# Bold the filename prefix
{$0=gensub(/^([^:]*:) /, "\e[1m\\1\e[0m ", "")}

