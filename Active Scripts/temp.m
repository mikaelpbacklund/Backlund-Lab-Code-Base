if ~exist('ex','var')
   ex = experiment;
end

%If there is no pulseBlaster object, create a new one with the config file "pulse_blaster_config"
if isempty(ex.pulseBlaster)
   ex.pulseBlaster = pulse_blaster('PB');
   ex.pulseBlaster = connect(ex.pulseBlaster);
end

%If there is no RF_generator object, create a new one with the config file "SRS_RF"
%This is the "normal" RF generator that our lab uses, other specialty RF generators have their own configs
if isempty(ex.SRS_RF)
   ex.SRS_RF = RF_generator('SRS_RF');
   ex.SRS_RF = connect(ex.SRS_RF);
end

%Windfreak connection
if isempty(ex.windfreak_RF)
   ex.windfreak_RF = RF_generator('windfreak_RF');
   ex.windfreak_RF = connect(ex.windfreak_RF);
end

%If there is no DAQ_controller object, create a new one with the config file "NI_DAQ_config"
if isempty(ex.DAQ)
   ex.DAQ = DAQ_controller('NI_DAQ');
   ex.DAQ = connect(ex.DAQ);
end

%Stage connection
if isempty(ex.PIstage) || ~ex.PIstage.connected
    ex.PIstage = stage('PI_stage');
    ex.PIstage = connect(ex.PIstage);
end