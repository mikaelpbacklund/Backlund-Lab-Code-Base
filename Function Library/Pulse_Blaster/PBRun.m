function [signal,reference] = PBRun
%Runs the current pulse sequence and records signal and reference data
%outputs

%PBRun v2.1 9/8/22

global master
global NIDAQ
pause(0.01)
InitializationCheck('PB')
InitializationCheck('NIDAQ')

%Suppresses unhelpful warning
warning('off','MATLAB:subscripting:noSubscriptsSpecified')

%Used for if data collection fails
collectData = true;
failCounter = 0;
pause(0.01)
while collectData
    try


        if master.NIDAQ.useClock
            if strcmp(master.comp,'NV2')
                disp('first')
                if ~NIDAQ.Running
                        start(NIDAQ,'continuous')
                end
                disp('second')

                %try
                    %n = 0;
                    %while n < 100
                        %fprintf('%d, ',n)
                        %n = n+1;
                        %pause(.01)
                    %end
                %catch ME
                    %master.debugging.tempError = ME;
                %end

                if ~isempty(NIDAQ.UserData)
                    %resets counters if they get super high
                    if NIDAQ.UserData(end,1) > 1e9
                        if master.notifications
                            fprintf('resetting counters')
                        end
                        stop(NIDAQ)
                        resetcounters(NIDAQ)
                        start(NIDAQ,'continuous')
                    end
                    nPreviousCounters = NIDAQ.UserData(end,1);
                else
                    nPreviousCounters = 0;
                end

                NIDAQ.UserData = [];

                calllib(master.PB.dllname,'pb_start');

                while calllib(master.PB.dllname,'pb_read_status') == 4
                    pause(.001)
                    if isfield(master,'gui') && isfield(master.gui,'interrupted') && master.gui.interrupted
                        fprintf('PBRun interrupted')
                        calllib(master.PB.dllname,'pb_stop');
                    end
                end

                if isfield(master,'debugging') && isfield(master.debugging,'manualDAQWait')
                    pause(master.debugging.manualDAQWait)
                end

                disp('fourth')

                ii = 0;
                while true
                    if ~isempty(NIDAQ.UserData) && sum(NIDAQ.UserData,"all") ~= 0
                        break
                    end
                    pause(.001)
                    ii = ii+1;
                    if ii > 1000
                        if isempty(NIDAQ.UserData)
                            error('Failed to get any data')
                        else
                            master.debugging.zeroData = NIDAQ.UserData;
                            warning('Failed to get non-zero data')
                        end
                        break
                    end
                end    

                disp('fifth')

                calllib(master.PB.dllname,'pb_stop');

                unsorted_data = NIDAQ.UserData;
                unsorted_data(:,1) = unsorted_data(:,1) - nPreviousCounters;
                
            else

                %Calculates number of points expected based on sequence duration
                npoints = ceil((master.PB.sequenceDuration/1e9) * master.NIDAQ.maxrate);

                %Begin pulse blaster sequence
                calllib(master.PB.dllname,'pb_start');

                %This will return a timetable after the specified number of
                %points have been acquired
                %Matlab will call this function then pause until it gets npoints
                %of data back
                unsorted_data = read(NIDAQ,npoints,"OutputFormat","Matrix");

                while calllib(master.PB.dllname,'pb_read_status') == 4
                    pause(.001)
                end
                if isfield(master,'debugging') && isfield(master.debugging,'switch') && master.debugging.switch
                    master.debugging.unsorted_data = unsorted_data;
                end

                %Stops running the pulse sequence as soon as the data has been collected
                [~]=calllib(master.PB.dllname,'pb_stop');
            end
            
            %% Data analysis (sig/ref)
            %Checks if there are any pulses where data is being acquired
            hasData = false;
            for ii = 1:numel(master.PB.sequence)
                currentBinary = master.PB.sequence(ii).binaryoutput(end-1);
                if strcmp(currentBinary,'1')
                    hasData = true;
                    break
                end
            end
            

            if hasData
                %Interprets the unsorted data into signal and reference
                [signal,reference] = NIDAQInterpreter(unsorted_data);
            else
                signal = 0;
                reference = 0;
            end

            if isfield(master,'gui') && isfield(master.gui,'interrupted') &&...
                    master.gui.interrupted && NIDAQ.Running && strcmp(master.comp,'NV2')
                stop(NIDAQ)
            end

        else
            resetcounters(NIDAQ)

            %Begin pulse blaster sequence
            calllib(master.PB.dllname,'pb_start');

            if master.NIDAQ.confocal

                %Accumulate counts as pulse sequence runs
                %             n = 0;
                while calllib(master.PB.dllname,'pb_read_status') == 4
                    pause(.001)
                    %                n = n+1;
                end

                %Read out counts as reference
                reference = read(NIDAQ);
                if strcmp(master.comp,"NV")
                    reference = reference.Dev1_ctr2;
                else
                    reference = reference.Dev2_ctr2;
                end

            else

                totalvoltage = 0;
                nreadings = 0;
                %While running, take measurement of voltage as fast as possible
                %and add that the total which can then take the average by
                %dividing by the number of measurements
                %             if isfield(master,'debugging') && isfield(master.debugging,'switch') && master.debugging.switch
                %                 master.debugging.voltage = [];
                %                 master.debugging.rawVoltage = [];
                %             end
                while calllib(master.PB.dllname,'pb_read_status') == 4
                    newdata = read(NIDAQ);
                    %                if etime(clock,master.debugging.lastClock) > 1
                    %                 master.debugging.PBStatus = calllib(master.PB.dllname,'pb_read_status');
                    %                 fprintf('taking data. status: %d\n',master.debugging.PBStatus)
                    %                 master.debugging.lastClock = clock;
                    %                end
                    if strcmp(master.comp,"NV")
                        data = newdata.Dev1_ai0;
                        %                    master.debugging.data(end+1) = data;
                        if isfield(master,'debugging') && isfield(master.debugging,'switch') && master.debugging.switch
                            master.debugging.rawVoltage(end+1) = data;
                        end
%                         if data > .001
                            totalvoltage = totalvoltage + data;
                            %                         if isfield(master,'debugging') && isfield(master.debugging,'switch') && master.debugging.switch
                            %                             master.debugging.voltage(end+1) = data;
                            %                         end
%                         end
                        nreadings = nreadings+1;
                    else
                        totalvoltage = totalvoltage + newdata.Dev2_ai0;
                        nreadings = nreadings+1;
                    end
                    %                if nreadings > 100
                    %                   break
                    %                end
                end

                if nreadings ~= 0
                    reference = totalvoltage/nreadings;
                else
                    reference = 0;
                end
                %             calllib(master.PB.dllname,'pb_read_status')

            end

            %Stops running the pulse sequence as soon as the data has been collected
            [~]=calllib(master.PB.dllname,'pb_stop');

            %Make signal equal reference as there is no differentiation while
            %the clock is off
            signal = reference;

        end

        if isfield(master,'debugging') && isfield(master.debugging,'baselineSubtraction')
           reference = reference - master.debugging.baselineSubtraction;
           signal = signal - master.debugging.baselineSubtraction;
        end

        %If the output value (voltage or counts) is below the set value, redo this data point. By default, the set value
        %is 0 meaning any counts will pass this and any positive voltage will as well
        if reference >= master.NIDAQ.removeOutlierValue           
           collectData = false;
        else
            warning('Outlier value detected, retrying data point')
        end
        

    catch ME
        [~]=calllib(master.PB.dllname,'pb_stop');
        failCounter = failCounter + 1;
        currTime = clock;
        fprintf('Data collection failed. Current time: %d:%d\n',currTime(4),currTime(5))
        fprintf('Collection has failed %d times\n',failCounter)
        fprintf('Error message: %s\n',ME.message)
        master.debugging.ME = ME;
        if exist("unsorted_data",'var')
            master.debugging.data = unsorted_data;
        end
        if failCounter > 0
            collectData = false;
            fprintf('Aborting collection attempts. Signal and reference will return as 0\n')
            signal = 0;
            reference = 0;
        end
    end

end



% if isfield(master,'debugging') && isfield(master.debugging,'switch') && master.debugging.switch
%     if reference ~= 0
%         master.debugging.fullDAQ = read(NIDAQ);
%         master.debugging.n = n;
%         error('got 0')
%     end
% end



end