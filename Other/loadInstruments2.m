function ex = loadInstruments2(ex,instrumentConfigs,varargin)
%Loads instruments given by instrumentNames using configs given by instrumentConfigs
%3rd argument is boolean on giving already present warning
%4th argument is string vector of equal length to instrumenntConfigs containing informal names

if isempty(ex)
   ex = experiment;
end

%Gives warning if instrument already exists and is connected
if nargin >= 3 && ~isempty(varargin{1})
   giveAlreadyPresentWarning = varargin{1};
else
   giveAlreadyPresentWarning = true;
end

instrumentConfigs = string(instrumentConfigs); 

for ii = 1:numel(instrumentConfigs)
   %Loads instrument config in order to get name and class
   load(instrumentConfigs(ii),"config")   

   %Changes informal name to display in console messages if 4th argument given
   if nargin >= 4 && ~isempty(varargin{2})
      informalName = varargin{2}(ii);
   else
      informalName = config.instrumentName;
   end

   if isempty(ex.(config.instrumentName))
      %Creates instrument of specified class using given config as a property of experiment
      fprintf('Connecting to %s...\n',informalName)
      ex.(config.instrumentName) = eval(sprintf('%s(instrumentConfigs(ii))',config.instrumentClass));
      ex.(config.instrumentName) = connect(ex.(config.instrumentName));
      fprintf('%s connected\n',informalName)
   elseif  ex.(config.instrumentName).connected == 0
      %If already present but not connected, connect to instrument
      fprintf('Connecting to %s...\n',informalName)
      ex.(config.instrumentName) = connect(ex.(config.instrumentName));
      fprintf('%s connected\n',informalName)
   elseif giveAlreadyPresentWarning
      warning('%s already present',informalName)
   end
end
end
