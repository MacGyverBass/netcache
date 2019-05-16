# Watch for the filename header and store the basename to a variable, then move to the next line
/^==> /{
	a=substr($0, 5, length($0)-8);
	a=gensub(/^.*\/([^\.]*)\..*$/, "\\1", "", a);
	next;
}

# If the string isn't empty, return the filename (from the variable) as a prefix to the current line
/./{
	$0=a": "$0
}

