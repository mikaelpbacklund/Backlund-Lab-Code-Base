%Example Spin Echo using template

%% User Settings
params.RFResonanceFrequency = 2.87;
params.piTime = 60;
params.tauStart = 200;
params.tauEnd = 1100;
params.tauStepSize = 50;
%All parameters below this are optional in that they will revert to defaults if not specified
params.tauNSteps = [];%will override step size
params.timePerDataPoint = 1;%seconds
params.collectionDuration = 1000;
params.collectionBufferDuration = 1000;
params.intermissionBufferDuration = 2500;
params.repolarizationDuration = 7000;
params.extraRF =  6;
params.AOM_DAQCompensation = 400;
params.IQPreBufferDuration = 10;
params.IQPostBufferDuration = 30;

nIterations = 1;
RFAmplitude = 10;
dataType = 'analog';
timeoutDuration = 10;
forcedDelayTime = .125;

%% Setup

%The following creates and connects to instruments
if ~exist('ex','var')
   ex = experiment_beta;
end

if isempty(ex.pulseBlaster)
   ex.pulseBlaster = pulse_blaster;
   ex.pulseBlaster = connect(ex.pulseBlaster,'pulse_blaster_config');
end

if isempty(ex.RF)
   ex.RF = RF_generator;
   ex.RF = connect(ex.RF,'RF_generator_config');
end

if isempty(ex.DAQ)
   ex.DAQ = DAQ_controller;
   ex.DAQ = connect(ex.DAQ,'NI_DAQ_config');
end

if isempty(ex.PIstage)
   ex.PIstage = stage;
   ex.PIstage = connect(ex.PIstage,'PI_stage_config');
end

%RF settings
ex.RF.enabled = 'on';
ex.RF.modulationEnabled = 'off';
ex.RF.amplitude = RFAmplitude;
ex.RF.frequency = params.RFResonanceFrequency;

%DAQ settings
ex.DAQ.takeData = false;
ex.DAQ.differentiateSignal = 'on';
ex.DAQ.activeDataChannel = dataType;

%Load empty parameter structure from template
[~,~,sentParams] = SpinEcho([],[]);

%Replaces values in sentParams with values in params if they aren't empty
for paramName = fieldnames(sentParams)'
   if ~isempty(params.(paramName{1}))
      sentParams.(paramName{1}) = params.(paramName{1});
   end
end

%Executes spin echo template, giving back edited pulse blaster object and information for the scan
[ex.pulseBlaster,scanInfo] = SpinEcho(ex.pulseBlaster,sentParams);

ex = addScans(ex,scanInfo);

%Adds time (in seconds) after pulse blaster has stopped running before continuing to execute code
ex.forcedCollectionPauseTime = forcedDelayTime;

%Prepares experiment to run from scratch
ex = resetAllData(ex);

%Checks if the current configuration is valid. This will give an error if not
ex = validateExperimentalConfiguration(ex,'pulse sequence');

%Sends information to command window
%First is the number of steps, second is the full time per data point, third is the number of iterations,
%fourth is a fudge factor for any additional time from various sources (heuristically found)
timerPerDataPoint = ex.pulseBlaster.sequenceDurations.sent.totalSeconds + ex.forcedCollectionPauseTime*1.5;
scanStartInfo(ex.scan.nSteps,timePerDataPoint,nIterations,.28)

cont = checkContinue(timeoutDuration*2);
if ~cont
   return
end

%% Run scan, and collect and display data

%Prepares experiment to run from scratch
%[0,0] is the value that all initial values for the data will take
%Two values are used because we are storing ref and sig
ex = resetAllData(ex,[0 0]);

for ii = 1:nIterations

   %Prepares scan for a fresh start while keeping data from previous
   %iterations
   [ex,instr] = resetScan(ex,instr);

   %While the odometer is not at its max value
   while ~all(ex.odometer == [ex.scan.nSteps])

      [ex,instr] = takeNextDataPoint(ex,instr,'pulse sequence');

      %Plot the average and new contrast for each data point
      plotTypes = {'average','new'};%'old' also viable
      for plotName = plotTypes
         c = findContrast(ex,[],plotName{1});
         ex = plotData(ex,c,plotName{1});
      end
   end

   if ii ~= nIterations
      cont = checkContinue(timeoutDuration);
      if ~cont
         break
      end
   end

end

%Stops continuous collection from DAQ
stop(instr{2}.handshake)

fprintf('Scan complete\n')