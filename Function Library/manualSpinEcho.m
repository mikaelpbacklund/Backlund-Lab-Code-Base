%% Global declarations
  
global master
global RFgen 
global NIDAQ
global coarseXYControl %#ok<*NUSED> 
global coarseZControl
global fineControl
global PIController

%global current_time
%% Settings
mSet = 1; % Number of averaging of frequency sweeps

%binary input vector in order: [Q, I, RF, Sig/ref indicator, collect Data,
%AOM]

%% RF Start

freq = 2.6;
pi_by_two_pulse_duration = 9; %ns
pi_pulse_duration = 2*pi_by_two_pulse_duration;
IQoverhang = 20;
tauStart = 150; %ns
tauEnd = 5000; 
nTau = 31;
tauSwept = round(linspace(tauStart,tauEnd,nTau));

MWamp = 10; %dBm

master.RFgen.amp = MWamp;
master.RFgen.ampunit = "dbm";
master.RFgen.freq = freq;
master.RFgen.switch = "off";
RFInitialization()

master.RFgen.amp = MWamp;
master.RFgen.ampunit = "dbm";
RFAmplitude()

master.RFgen.switch = "on";
RFSwitch()

% Setting frequency
master.RFgen.freq = freq;
RFFrequency()
pause(0.1)

%% Main loop
contrast = zeros(1,length(tauSwept));
count_off = zeros(1,length(tauSwept));
count_on = zeros(1,length(tauSwept));

prev_timestamp = clock;
kk=0;

% for mm = 1:4
%     stageOptimization()
% end
countlog = 0;

for ii = 1:mSet
    
    %If more than 2 minutes have passed since the previous timestamp, run
    %an optimization then set new "previous" timestamp
    timestamp = clock;
%     if etime(timestamp,prev_timestamp) > 60*2
%         PIStageOptimization()
%         prev_timestamp = clock;
%         kk=kk+1;
%         countlog(end+1) = master.stage.optvallog(end); %#ok<SAGROW>
%     end
        
    disp(ii);
    
    for jj = 1:length(tauSwept)
                
        % Resetting DAQ counts
        resetcounters(NIDAQ);
        
        % Loading time sequence
        current_tau = tauSwept(jj);
        display(current_tau)
         
        pp =1; %not sure if this should start at 0 or 1

        % Pulse Blaster
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%% Buffer %%%%%%%%%%%%%%%%%%%%%%%%%%%%
        master.PB.command.address = pp;
        master.PB.command.output = 0;%"0";
        master.PB.command.direction = 'CONTINUE';
        master.PB.command.duration = 5e6;
        PBAddSequence()
        pp = pp + 1;
        
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%% Loop Begins %%%%%%%%%%%%%%%%%%%%%%%
        master.PB.command.address = pp;
        master.PB.command.output = 10;%"0";
        master.PB.command.direction = 'LOOP';
        master.PB.command.duration = 100;
        master.PB.command.contextinfo = 10000; 
        PBAddSequence()
        pp = pp + 1;
        
        %%%%%%%%%%%%%%%%%%%%% Main RF part - Ref side %%%%%%%%%%%%%%%%%%%%
        for issignal = 0:1
            
            %do nothing for a microsecond
            master.PB.command.address = pp;
            master.PB.command.output = "0";
            master.PB.command.direction = 'CONTINUE';
            master.PB.command.duration = 1000;
            PBAddSequence()
            pp = pp + 1;
        
            %%
            %first pi/2 pulse
            
            master.PB.command.address = pp;
            Qison = 0;
            Iison = 0;
            RFison = 0;
            collectData = 0;
            AOMison = 0;
            binaryoutput = [Qison, Iison, RFison, issignal, collectData, AOMison];
            master.PB.command.output = binaryVectorToHex(binaryoutput);
            master.PB.command.direction = 'CONTINUE';
            master.PB.command.duration = IQoverhang;
            PBAddSequence()
            pp = pp + 1;
            
            master.PB.command.address = pp;
            Qison = 0;
            Iison = 0;
            RFison = 1;
            collectData = 0;
            AOMison = 0;
            binaryoutput = [Qison, Iison, RFison, issignal, collectData, AOMison];
            master.PB.command.output = binaryVectorToHex(binaryoutput);
            master.PB.command.direction = 'CONTINUE';
            master.PB.command.duration = pi_by_two_pulse_duration;
            PBAddSequence()
            pp = pp + 1;
            
            master.PB.command.address = pp;
            Qison = 0;
            Iison = 0;
            RFison = 0;
            collectData = 0;
            AOMison = 0;
            binaryoutput = [Qison, Iison, RFison, issignal, collectData, AOMison];
            master.PB.command.output = binaryVectorToHex(binaryoutput);
            master.PB.command.direction = 'CONTINUE';
            master.PB.command.duration = IQoverhang;
            PBAddSequence()
            pp = pp + 1;
            
            %%
            %first waiting time
            master.PB.command.address = pp;
            Qison = 0;
            Iison = 0;
            RFison = 0;
            collectData = 0;
            AOMison = 0;
            binaryoutput = [Qison, Iison, RFison, issignal, collectData, AOMison];
            master.PB.command.output = binaryVectorToHex(binaryoutput);
            master.PB.command.direction = 'CONTINUE';
            master.PB.command.duration = round(current_tau - pi_by_two_pulse_duration/2 - pi_pulse_duration/2 - 2*IQoverhang);
            PBAddSequence()
            pp = pp + 1;
            
            %%
            %pi pulse
            
            master.PB.command.address = pp;
            Qison = 0;
            Iison = 1;
            RFison = 0;
            collectData = 0;
            AOMison = 0;
            binaryoutput = [Qison, Iison, RFison, issignal, collectData, AOMison];
            master.PB.command.output = binaryVectorToHex(binaryoutput);
            master.PB.command.direction = 'CONTINUE';
            master.PB.command.duration = IQoverhang;
            PBAddSequence()
            pp = pp + 1;
            
            master.PB.command.address = pp;
            Qison = 0;
            Iison = 1;
            RFison = 1;
            collectData = 0;
            AOMison = 0;
            binaryoutput = [Qison, Iison, RFison, issignal, collectData, AOMison];
            master.PB.command.output = binaryVectorToHex(binaryoutput);
            master.PB.command.direction = 'CONTINUE';
            master.PB.command.duration = pi_pulse_duration;
            PBAddSequence()
            pp = pp + 1;
            
            master.PB.command.address = pp;
            Qison = 0;
            Iison = 1;
            RFison = 0;
            collectData = 0;
            AOMison = 0;
            binaryoutput = [Qison, Iison, RFison, issignal, collectData, AOMison];
            master.PB.command.output = binaryVectorToHex(binaryoutput);
            master.PB.command.direction = 'CONTINUE';
            master.PB.command.duration = IQoverhang;
            PBAddSequence()
            pp = pp + 1;
            
            %%
            %second waiting time
            master.PB.command.address = pp;
            Qison = 0;
            Iison = 0;
            RFison = 0;
            collectData = 0;
            AOMison = 0;
            binaryoutput = [Qison, Iison, RFison, issignal, collectData, AOMison];
            master.PB.command.output = binaryVectorToHex(binaryoutput);
            master.PB.command.direction = 'CONTINUE';
            master.PB.command.duration = round(current_tau - pi_by_two_pulse_duration/2 - pi_pulse_duration/2 - 2*IQoverhang);
            PBAddSequence()
            pp = pp + 1;
            
            %%
            %second pi/2 pulse
            
            master.PB.command.address = pp;
            Qison = issignal;
            Iison = issignal;
            RFison = 0;
            collectData = 0;
            AOMison = 0;
            binaryoutput = [Qison, Iison, RFison, issignal, collectData, AOMison];
            master.PB.command.output = binaryVectorToHex(binaryoutput);
            master.PB.command.direction = 'CONTINUE';
            master.PB.command.duration = IQoverhang;
            PBAddSequence()
            pp = pp + 1;
            
            master.PB.command.address = pp;
            Qison = issignal;
            Iison = issignal;
            RFison = 1;
            collectData = 0;
            AOMison = 0;
            binaryoutput = [Qison, Iison, RFison, issignal, collectData, AOMison];
            master.PB.command.output = binaryVectorToHex(binaryoutput);
            master.PB.command.direction = 'CONTINUE';
            master.PB.command.duration = pi_by_two_pulse_duration;
            PBAddSequence()
            pp = pp + 1;
            
            master.PB.command.address = pp;
            Qison = issignal;
            Iison = issignal;
            RFison = 0;
            collectData = 0;
            AOMison = 0;
            binaryoutput = [Qison, Iison, RFison, issignal, collectData, AOMison];
            master.PB.command.output = binaryVectorToHex(binaryoutput);
            master.PB.command.direction = 'CONTINUE';
            master.PB.command.duration = IQoverhang;
            PBAddSequence()
            pp = pp + 1;
            
            %%
            %do nothing for a microsecond
            master.PB.command.address = pp;
            master.PB.command.output = "0";
            master.PB.command.direction = 'CONTINUE';
            master.PB.command.duration = 1000;
            PBAddSequence()
            pp = pp + 1;
            
            %%
            %start read
            master.PB.command.address = pp;
            Qison = 0;
            Iison = 0;
            RFison = 0;
            collectData = 1;
            AOMison = 0;
            binaryoutput = [Qison, Iison, RFison, issignal, collectData, AOMison];
            master.PB.command.output = binaryVectorToHex(binaryoutput);
            master.PB.command.direction = 'CONTINUE';
            master.PB.command.duration = 100;
            PBAddSequence()
            pp = pp + 1;
            
            %continue read
            master.PB.command.address = pp;
            Qison = 0;
            Iison = 0;
            RFison = 0;
            collectData = 1;
            AOMison = 1;
            binaryoutput = [Qison, Iison, RFison, issignal, collectData, AOMison];
            master.PB.command.output = binaryVectorToHex(binaryoutput);
            master.PB.command.direction = 'CONTINUE';
            master.PB.command.duration = 900;
            PBAddSequence()
            pp = pp + 1;
            
            %continue repolarization
            master.PB.command.address = pp;
            Qison = 0;
            Iison = 0;
            RFison = 0;
            collectData = 0;
            AOMison = 1;
            binaryoutput = [Qison, Iison, RFison, issignal, collectData, AOMison];
            master.PB.command.output = binaryVectorToHex(binaryoutput);
            master.PB.command.direction = 'CONTINUE';
            master.PB.command.duration = 7500-900;
            PBAddSequence()
            pp = pp + 1;
        end
%%
        %%%%%%%%%%%%% Loop ends %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        master.PB.command.address = pp;
        master.PB.command.output = "0";
        master.PB.command.direction = 'END_LOOP';
        master.PB.command.duration = 100;
        master.PB.command.contextinfo = 1; 
        PBAddSequence()
        pp = pp + 1;

        master.PB.command.address = pp;
        master.PB.command.output = "0";
        master.PB.command.direction = 'CONTINUE';
        master.PB.command.duration = 100;
        PBAddSequence()
        pp = pp + 1;

        master.PB.command.address = pp;
        master.PB.command.output = "0";
        master.PB.command.direction = 'STOP';
        master.PB.command.duration = 100;
        PBAddSequence()
        pp = pp + 1;

        PBFinalize()
        
        resetcounters(NIDAQ);
        
        % Pulse Blaster
        [signal_var, reference] = PBRunMain();
        
        contrast(jj) = contrast(jj) + signal_var - reference;
        count_off(jj) =  count_off(jj) + reference;
        count_on(jj) = count_on(jj) + signal_var;
        clear daqout;
        
        %pause(5);
        plot (t, contrast./count_off);
        %plot (t, count_off);
        title(sprintf('Set %d',ii));
        %plot (freqs, count_off);
        
    end
    
end

