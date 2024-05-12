#!/bin/awk -f
# Substitute references to environment variables in the form of ${VARIABLE} or ${VARIABLE:-default_value} with their values
BEGIN {
    regex="\\${[a-zA-Z0-9_]+(:-.*){0,1}}";
}
{
    s = $0;
    new_s = "";

    while (match(s,regex)) {
        # RSTART is where the pattern starts
        # RLENGTH is the length of the pattern
        before = substr(s,1,RSTART-1);
        pattern = substr(s,RSTART,RLENGTH);
        after = substr(s,RSTART+RLENGTH);

        # Add 'before' string to a new one
        new_s = new_s before;

        # Use pattern as a value initially
        pattern_value = pattern;

        # If we have a default value, extract it as pattern_value and remove it from the pattern
        start_of_default = index(pattern,":-");
        if (start_of_default) {
            pattern_value = substr(pattern,start_of_default+2,length(pattern)-(start_of_default+2));
            pattern = substr(pattern,1,start_of_default-1) "}";
        }

        # Try to find an environment variable from pattern
        # If found, replace it with its value
        env_name = substr(pattern,3,length(pattern)-3);
        if (env_name in ENVIRON) {
            env_value = ENVIRON[env_name];
            pattern_value = env_value;
        }

        new_s = new_s pattern_value;

        # Use 'after' for subsequent searches
        s = after;
    }

    # Add the rest of the string
    new_s = new_s s;

    print new_s;
}
