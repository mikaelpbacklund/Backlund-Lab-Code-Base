function continueTrueFalse = checkContinue(timeoutDelay,varargin)
%Checks if user wants to continue after an optional timeout

opts = parseCheckContinueOptions(timeoutDelay,varargin{:});

% Changed: added a unattended path that returns immediately instead of using
% the auto-keypress timer. This was added so overnight runs can skip
% prompts without leaving MATLAB sitting inside input(). -Div
if opts.nonInteractive
   continueTrueFalse = true;
   return
end

% Changed: added an explicit option to disable timeout auto-continue and fall back
% to a normal blocking prompt. Previously every timed prompt relied on auto input. -Div
if ~opts.autoContinueOnTimeout || isempty(opts.timeoutDelay) || opts.timeoutDelay <= 0
   continueTrueFalse = input('Continue? 0 or 1\n');
   return
end

%Gets current pseudo-global data then sets robotPressKeys to true to allow timeout
data = pseudoGlobalData([]);
data.robotPressKeys = true;
[~] = pseudoGlobalData(data);

continueStopwatch = tic; %start timer to cancel timeout

%Begin timer which will default to continue after timeoutDelay seconds
iterationTimer = timer('StartDelay', opts.timeoutDelay, 'TimerFcn', @iterationTimeout);
start(iterationTimer)

%Asks for user input
continueTrueFalse = input('Continue? 0 or 1\n');

if toc(continueStopwatch) < opts.timeoutDelay
   %Turn off timeout key presses if timeout didn't happen
   data = pseudoGlobalData([]);
   data.robotPressKeys = false;
   [~] = pseudoGlobalData(data);
end

if isvalid(iterationTimer)
   stop(iterationTimer)
   delete(iterationTimer)
end
end

function opts = parseCheckContinueOptions(timeoutDelay,varargin)
% Added: option parsing for nonInteractive and autoContinueOnTimeout so the shared
% prompt helper can support unattended scans without duplicating logic. -Div
opts.timeoutDelay = timeoutDelay;
opts.nonInteractive = false;
opts.autoContinueOnTimeout = true;

if isempty(varargin)
   return
end

if isstruct(varargin{1})
   sentOptions = varargin{1};
   optionNames = fieldnames(sentOptions);
   for ii = 1:numel(optionNames)
      opts = applyCheckContinueOption(opts,optionNames{ii},sentOptions.(optionNames{ii}));
   end
   return
end

if rem(numel(varargin),2) ~= 0
   error('checkContinue options must be provided as name/value pairs')
end

for ii = 1:2:numel(varargin)
   opts = applyCheckContinueOption(opts,varargin{ii},varargin{ii+1});
end
end

function opts = applyCheckContinueOption(opts,optionName,optionValue)
switch lower(string(optionName))
   case "noninteractive"
      opts.nonInteractive = logical(optionValue);
   case {"autocontinue","autocontinueontimeout"}
      opts.autoContinueOnTimeout = logical(optionValue);
   case {"timeout","timeoutdelay"}
      opts.timeoutDelay = optionValue;
   otherwise
      error('Unknown checkContinue option "%s"',string(optionName))
end
end
