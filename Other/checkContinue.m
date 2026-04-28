function continueTrueFalse = checkContinue(timeoutDelay)
%Checks if user wants to continue with a 5 second timeout

%Gets current pseudo-global data then sets robotPressKeys to true to allow timeout
data = pseudoGlobalData([]);
data.robotPressKeys = true;
[~] = pseudoGlobalData(data);

continueStopwatch = tic; %start timer to cancel timeout

%Begin timer which will default to continue after timeoutDelay seconds
iterationTimer = timer('StartDelay', timeoutDelay, 'TimerFcn', @iterationTimeout);
start(iterationTimer)

%Create a backup timer for the cases where the first timer is interrupted
iterationTimerBackup = timer('StartDelay', timeoutDelay*5, 'TimerFcn', @iterationTimeout);
start(iterationTimerBackup)

%Asks for user input
continueTrueFalse = input('Continue? 0 or 1\n');

if toc(continueStopwatch) < 5 %Check if timeout happened or not
   %Turn off timeout key presses if timeout didn't happen
   data = pseudoGlobalData([]);
   data.robotPressKeys = false;
   [~] = pseudoGlobalData(data);
end

stop(iterationTimer)
delete(iterationTimer)
stop(iterationTimerBackup)
delete(iterationTimerBackup)
end