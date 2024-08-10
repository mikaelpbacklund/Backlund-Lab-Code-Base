%Default ODMR script example

%This warning *should* be suppressed in the DAQ code but isn't for an unknown reason. This is not related to my code but
%rather the data acquisition toolbox code which I obviously can't change
warning('off','MATLAB:subscripting:noSubscriptsSpecified');

%Creates experiment object if none exist
if ~exist('ex','var')
   ex = experiment;
end

%If there is no pulseBlaster object, create a new one with the config file "pulse_blaster_config"
if isempty(ex.pulseBlaster)
   ex.pulseBlaster = pulse_blaster;
   ex.pulseBlaster = connect(ex.pulseBlaster,'pulse_blaster_config');
end

%If there is no RF_generator object, create a new one with the config file "SRS_RF"
%This is the "normal" RF generator that our lab uses, other specialty RF generators have their own configs
if isempty(ex.SRS_RF)
   ex.SRS_RF = RF_generator;
   ex.SRS_RF = connect(ex.SRS_RF,'RF_generator_config');
end

%If there is no DAQ_controller object, create a new one with the config file "NI_DAQ_config"
if isempty(ex.DAQ)
   ex.DAQ = DAQ_controller;
   ex.DAQ = connect(ex.DAQ,'NI_DAQ_config');
end

%Turns RF on, disables modulation, and sets amplitude to 10 dBm
ex.SRS_RF.enabled = 'on';
ex.SRS_RF.modulationEnabled = 'off';
ex.SRS_RF.amplitude = 10;

%Temporarily disables taking data, differentiates signal and reference (to get contrast), and sets data channel to
%counter
ex.DAQ.takeData = false;
ex.DAQ.differentiateSignal = 'on';
ex.DAQ.activeDataChannel = 'counter';

%Sets loops for entire sequence to "on" and for 300. Deletes previous sequence if any existed
ex.pulseBlaster.nTotalLoops = 300;
ex.pulseBlaster.useTotalLoop = true;
ex.pulseBlaster.userSequence = [];

%For each of the following sections:
%Clear previous information
%Set which channels should be active in the pulse blaster
%Set how long this pulse should run for
%List any notes to describe the pulse
%Add the pulse to the current sequence
clear pulseInfo 
pulseInfo.activeChannels = {};
pulseInfo.duration = 2500;
pulseInfo.notes = 'Initial buffer';
ex.pulseBlaster = addPulse(ex.pulseBlaster,pulseInfo);

clear pulseInfo 
pulseInfo.activeChannels = {'AOM','DAQ'};
pulseInfo.duration = 1e6;
pulseInfo.notes = 'Reference';
ex.pulseBlaster = addPulse(ex.pulseBlaster,pulseInfo);

clear pulseInfo 
pulseInfo.activeChannels = {};
pulseInfo.duration = 2500;
pulseInfo.notes = 'Middle buffer signal off';
ex.pulseBlaster = addPulse(ex.pulseBlaster,pulseInfo);

clear pulseInfo 
pulseInfo.activeChannels = {'Signal'};
pulseInfo.duration = 2500;
pulseInfo.notes = 'Middle buffer signal on';
ex.pulseBlaster = addPulse(ex.pulseBlaster,pulseInfo);

clear pulseInfo 
pulseInfo.activeChannels = {'AOM','DAQ','RF','Signal'};
pulseInfo.duration = 1e6;
pulseInfo.notes = 'Signal';
ex.pulseBlaster = addPulse(ex.pulseBlaster,pulseInfo);

clear pulseInfo 
pulseInfo.activeChannels = {'Signal'};
pulseInfo.duration = 2500;
pulseInfo.notes = 'Final buffer';
ex.pulseBlaster = addPulse(ex.pulseBlaster,pulseInfo);

%Sends the currently saved pulse sequence to the pulse blaster instrument itself
ex.pulseBlaster = sendToInstrument(ex.pulseBlaster);

%Deletes any pre-existing scan
ex.scan = [];

scan.bounds = [2.5 3]; %RF frequency bounds
scan.stepSize = .005; %Step size for RF frequency
scan.parameter = 'frequency'; %Scan frequency parameter
scan.instrument = 'RF_generator'; %Instrument is of class 'RF_generator'
scan.identifier = 'SRS RF'; %Instrument has identifier 'SRS RF' (not needed if only one RF generator is connected)
scan.notes = 'ODMR'; %Notes describing scan (will appear in titles for plots)

%Add the current scan
ex = addScans(ex,scan);

%Adds time (in seconds) after pulse blaster has stopped running before continuing to execute code
ex.forcedCollectionPauseTime = .05;

%Checks if the current configuration is valid. This will give an error if not
ex = validateExperimentalConfiguration(ex,'pulse sequence');

%Sends information to command window
fprintf('Number of steps in scan: %d\n',ex.scan.nSteps)

%Total number of times the scan will be run
nIterations = 1;

%Resets current data. [0,0] is for reference and contrast counts
ex = resetAllData(ex,[0,0]);

for ii = 1:nIterations
   
   %Reset current scan each iteration
   ex = resetScan(ex);
   
   while ~all(ex.odometer == [ex.scan.nSteps]) %While odometer does not match max number of steps

      %Takes the next data point. This includes incrementing the odometer and setting the instrument to the next value
      ex = takeNextDataPoint(ex,'pulse sequence');      

      %Creates plots
      plotTypes = {'average','new','old'};
      for plotName = plotTypes
         c = findContrast(ex,plotName{1});
         ex = plotData(ex,c,plotName{1});
      end
      refData = cell2mat(cellfun(@(x)x(1),ex.data.current,'UniformOutput',false));
      ex = plotData(ex,refData,'reference');      
   end

   %Between each iteration, check for user input whether to continue scan
   %5 second timeout
   if ii ~= nIterations
       if ~checkContinue(5)
           break
       end
   end
end

stop(ex.DAQ.handshake)

