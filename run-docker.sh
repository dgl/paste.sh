#!/bin/sh

# Start the server in the background
twiggy --listen :5000 &
# use this to have more useful logs
# plackup -s Twiggy -a app.psgi &

# Get the process ID
PROCESS_PID=$!

# Wait for a brief moment to ensure the server starts
sleep 2

# Run the update script
./update-misc

sleep 2

# Wait for the PROCESS process to finish
wait $PROCESS_PID