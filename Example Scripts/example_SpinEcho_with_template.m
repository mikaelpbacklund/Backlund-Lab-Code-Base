%Example Spin Echo using template

%Parameters
rfFrequency = 2.87;
piTime = 60;
startTauDuration = 200;
endTauDuration = 1100;
tauStepSize = 50;
nIterations = 1;

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
ex.RF.amplitude = 10;

%DAQ settings
ex.DAQ.takeData = false;
ex.DAQ.differentiateSignal = 'on';
ex.DAQ.activeDataChannel = 'counter';

%Get parameters and defaults
[~,~,params] = SpinEcho([],[]);

%Finds the location of matching parameter then sets it according to inputs at beginning of script
parameterLocation = contains(lower(params(:,1)),'frequency');
params{parameterLocation,2} = rfFrequency;

parameterLocation = contains(lower(params(:,1)),'π');
params{parameterLocation,2} = piTime;

parameterLocation = contains(lower(params(:,1)),'start');
params{parameterLocation,2} = startTauDuration;

parameterLocation = contains(lower(params(:,1)),'end');
params{parameterLocation,2} = endTauDuration;

parameterLocation = contains(lower(params(:,1)),'steps');
params{parameterLocation,2} = tauStepSize;

%Executes spin echo template, giving back edited pulse blaster object and information for the scan
[ex.pulseBlaster,scanInfo] = SpinEcho(ex.pulseBlaster,params);

ex = addScans(ex,scanInfo);

%Sets RF frequency. Could have been done with initial paramter at top of script, but this is a demonstration of the
%template
ex.RF.frequency = scanInfo.RFfrequency;

%Type of stage optimization
optSequence.consecutive = true;

%Assignment of stage optimization sequence
optSequence.axes = {'x','y','z'};
optSequence.steps = {-1:.1:1,-1:.1:1,-2:.2:2};

%Prepares experiment to run from scratch
ex = resetAllData(ex);

%% Data collection and display

for ii = 1:nIterations
   
   %Prepares scan for a fresh start while keeping data from previous
   %iterations
   [ex,instrumentCells] = resetScan(ex,instrumentCells);
   
   %Runs initial optimization. Optimization goes to highest value based on
   %output of pulse sequence; the stage movements are determined by
   %optSequence and RF is turned off
   [ex,instrumentCells] = stageOptimization(ex,instrumentCells,'max value','pulse sequence',optSequence,'off');
   lastOptTime = datetime;
   
   %While the odometer is not at its max value
   while all(ex.odometer == [ex.scan.nSteps])
      
      if datetime-lastOptTime > duration(0,5,0)%Check if last optimization was over 5 mins ago
         %Runs stage optimization
         [ex,instrumentCells] = stageOptimization(ex,instrumentCells,'max value','pulse sequence',optSequence,'off');
         
         %Sets new time for last optimization
         lastOptTime = datetime;
      end
      
      [ex,instrumentCells] = takeNextDataPoint(ex,instrumentCells,'pulse sequence');
      
      %Display the data for the current iteration, the previous iterations,
      %and the average of all
      ex = displayData(ex,'current');
      ex = displayData(ex,'previous');
      ex = displayData(ex,'average');
   end
   
end




