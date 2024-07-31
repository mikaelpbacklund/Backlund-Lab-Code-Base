

zLocation = 6304;



%This warning *should* be suppressed in the DAQ code but isn't for an
%unknown reason. This is not related to my code but rather the data
%acquisition toolbox code which I obviously can't change
warning('off','MATLAB:subscripting:noSubscriptsSpecified');


if ~exist('instr','var')
   instr{1} = RF_generator;
   instr{1} = connect(instr{1},'RF_generator_config');
   instr{2} = DAQ_controller;
   instr{2} = connect(instr{2},'NI_DAQ_config');
   instr{3} = pulse_blaster;
   instr{3} = connect(instr{3},'pulse_blaster_config');
   instr{4} = stage;
   instr{4} = connect(instr{4},'PI_stage_config');
end
instr{1} = toggle(instr{1},'on');
instr{1} = modulationToggle(instr{1},'off');
instr{1} = setAmplitude(instr{1},10);
instr{1} = setFrequency(instr{1},RFFrequency);
instr{2} = setSignalDifferentiation(instr{2},'on');
instr{2} = setDataChannel(instr{2},'counter');
instr{2}.continuousCollection = false;
instr{2} = setSignalDifferentiation(instr{2},'off');
instr{2} = resetDAQ(instr{2});
if ~exist('ex','var')
   ex = experiment;
end
ex = validExperimentalConfiguration(ex,instr,'pulse sequence');


instr{4} = absoluteMove(instr{4},'Z',zLocation);


%pb shorthand used for simplicity and brevity. It will be re-synced with
%instrumentCells later
instr{3}.nTotalLoops = 3000;
instr{3}.userSequence = [];%Deletes whatever the current sequence is

clear pulseInfo 
pulseInfo.activeChannels = {'AOM','DAQ'};
pulseInfo.duration = 1e5;
pulseInfo.notes = 'Reference';
instr{3} = addPulse(instr{3},pulseInfo);

instr{3} = sendToInstrument(instr{3});


scan = [];
ex.scan = [];

scan.bounds = [-5130 -5110];
scan.stepSize = 1;
scan.parameter = 'X';
scan.instrument = 'stage';
scan.notes = 'x scan';

ex = addScans(ex,scan);

fprintf('Number of steps in scan: %d\n',ex.scan.nSteps(1))

% ex.scan = [];
% 
% %Since the in-focus value of z changes as a function of x, change z in
% %addition to x
% scan.bounds{1} = [-2600 -2500];
% scan.parameter{1} = 'X';
% scan.bounds{2} = [7000 7100];
% scan.parameter{2} = 'Z';
% %Don't need to specify second step size as the correct step size can be
% %computed by finding the number of steps for the x scan and applying that
% %number to get the step size of the z scan
% scan.stepSize(1) = 1; 
% scan.instrument = 'stage';
% scan.notes = 'x scan';
% 
% ex = addScans(ex,scan);

nIterations = 1;

%Prepares experiment to run from scratch
ex = resetAllData(ex,0);

for ii = 1:nIterations
   
   %Prepares scan for a fresh start while keeping data from previous
   %iterations
   [ex,instr] = resetScan(ex,instr);
   
   %While the odometer is not at its max value
   while ~all(ex.odometer == [ex.scan.nSteps])      
      
      [ex,instr] = takeNextDataPoint(ex,instr,'pulse sequence');

      data = cellfun(@(x,y)x(1)+y(1),ex.data.current,ex.data.previous);
      data = data ./ ex.data.iteration;
      data(isnan(data)) = 0;

       ex = make1DPlot(ex,data,'current');
      
      %Display the data for the current iteration, the previous iterations,
%       %and the average of all
%       ex = displayData(ex,'current');
%       ex = displayData(ex,'previous');
%       ex = displayData(ex,'average');
   end
   
end

fprintf('Scan complete\n')

%% Z scan

%Runs a simple 1D stage scan and displays the results


%This warning *should* be suppressed in the DAQ code but isn't for an
%unknown reason. This is not related to my code but rather the data
%acquisition toolbox code which I obviously can't change
warning('off','MATLAB:subscripting:noSubscriptsSpecified');


if ~exist('instr','var')
   instr{1} = RF_generator;
   instr{1} = connect(instr{1},'RF_generator_config');
   instr{2} = DAQ_controller;
   instr{2} = connect(instr{2},'NI_DAQ_config');
   instr{3} = pulse_blaster;
   instr{3} = connect(instr{3},'pulse_blaster_config');
   instr{4} = stage;
   instr{4} = connect(instr{4},'PI_stage_config');
end
instr{1} = toggle(instr{1},'on');
instr{1} = modulationToggle(instr{1},'off');
instr{1} = setAmplitude(instr{1},10);
instr{1} = setFrequency(instr{1},RFFrequency);
instr{2} = setDataChannel(instr{2},'counter');
instr{2}.continuousCollection = false;
instr{2} = setSignalDifferentiation(instr{2},'off');
instr{2} = resetDAQ(instr{2});
if ~exist('ex','var')
   ex = experiment;
end
ex = validExperimentalConfiguration(ex,instr,'pulse sequence');


%pb shorthand used for simplicity and brevity. It will be re-synced with
%instrumentCells later
instr{3}.nTotalLoops = 10000;
instr{3}.userSequence = [];%Deletes whatever the current sequence is

clear pulseInfo 
pulseInfo.activeChannels = {'AOM','DAQ'};
pulseInfo.duration = 1e5;
pulseInfo.notes = 'Reference';
instr{3} = addPulse(instr{3},pulseInfo);

instr{3} = sendToInstrument(instr{3});


scan = [];
ex.scan = [];

scan.bounds = [6300 6320];
scan.stepSize = .1;
scan.parameter = 'Z';
scan.instrument = 'stage';
scan.notes = 'z scan';

ex = addScans(ex,scan);

fprintf('Number of steps in scan: %d\n',ex.scan.nSteps(1))

% ex.scan = [];
% 
% %Since the in-focus value of z changes as a function of x, change z in
% %addition to x
% scan.bounds{1} = [-2600 -2500];
% scan.parameter{1} = 'X';
% scan.bounds{2} = [7000 7100];
% scan.parameter{2} = 'Z';
% %Don't need to specify second step size as the correct step size can be
% %computed by finding the number of steps for the x scan and applying that
% %number to get the step size of the z scan
% scan.stepSize(1) = 1; 
% scan.instrument = 'stage';
% scan.notes = 'x scan';
% 
% ex = addScans(ex,scan);

nIterations = 1;

%Prepares experiment to run from scratch
ex = resetAllData(ex,0);

for ii = 1:nIterations
   
   %Prepares scan for a fresh start while keeping data from previous
   %iterations
   [ex,instr] = resetScan(ex,instr);
   
   %While the odometer is not at its max value
   while ~all(ex.odometer == [ex.scan.nSteps])      
      
      [ex,instr] = takeNextDataPoint(ex,instr,'pulse sequence');

      data = cellfun(@(x,y)x(1)+y(1),ex.data.current,ex.data.previous);
      data = data ./ ex.data.iteration;
      data(isnan(data)) = 0;

       ex = make1DPlot(ex,data,'current');
      
      %Display the data for the current iteration, the previous iterations,
%       %and the average of all
%       ex = displayData(ex,'current');
%       ex = displayData(ex,'previous');
%       ex = displayData(ex,'average');
   end
   
end

fprintf('Scan complete\n')















