function [signal,reference] = NIDAQInterpreter(unsortedData)
%Interprets data output from DAQ into signal and reference. Designed to
%work within PBRun function with sequences. Unsorted data should be a
%two column matrix where the first column is the number of counts and the
%second is the voltage.
%Outputs sum of signal and sum of reference counts for confocal scans while
%outputting average signal and average reference voltage for wide field

%Instrument dependencies:
%NIDAQ
%Pulse blaster

%Code dependencies:

%NIDAQInterpreter v2.0 9/7/22

global master
global NIDAQ

%% Confocal
if master.NIDAQ.confocal
    if strcmp(master.comp,'NV2')
        reference = sum(NIDAQ.UserData(:,1));
        signal = sum(NIDAQ.UserData(:,2));
    else
%         assignin('base',"unsortedData",unsortedData)
   cutoffVoltage = 1.5; %Signal vs reference voltage cutoff
   ctrdiff = diff(unsortedData(:,1)); %Difference in number of counts
   unsortedData(1,:) = []; %Deletes first line for simplicity
   %Add up all the changes in the number of counts where the voltage is
   %less/greater than the cutoff which will be the reference/signal
   reference = sum(ctrdiff(unsortedData(:,2) <= cutoffVoltage)); 
   signal = sum(ctrdiff(unsortedData(:,2) > cutoffVoltage));
    end
end

%% Wide Field
if ~master.NIDAQ.confocal
    assignin('base',"unsortedData",unsortedData)
    try
   ndata = [0 0]; %Number of data points for signal and reference
   sortdata = [0 0]; %Sum of signal and reference
   ctrdiff = diff(unsortedData(:,1)); %Difference between every point and the previous
   unsortedData(1,:) = []; %Delete the first line for simplicity
   ctrincs = find(ctrdiff ~= 0); %Locates counter increments
   cntincs = ctrdiff(ctrincs); %Determines number of counts corresponding to each location of counter increment
   nn = 1; %Counting variable similar to for loop

   if ~isempty(cntincs)
   
   %Not a for loop of length cntincs because back to back increases of 1
   %would throw this off
   while true
      
       if cntincs(nn) == 1 %Counter increases by 1
          if ctrincs(nn+1) == ctrincs(nn)+1 || ctrincs(nn+1) == ctrincs(nn)+2 %Next increase is directly after (signal)
             sigref = 2; 
             nn = nn+1;
          else %Reference
             sigref = 1;   
          end
       else %Counter increases by 2 (signal)
          sigref = 2;
       end
      
      
      %Finds current range between increments and obtains the average
      %voltage within that range while the digital counter is on
      currRange = [ctrincs(nn) ctrincs(nn+1)-1];
      currData = unsortedData(currRange(1):currRange(2),:);
      if isfield(master,'debugging') && isfield(master.debugging,'switch') && master.debugging.switch
        master.debugging.currData1 = currData;
      end
      currData = currData(currData(:,3) == 1,2);
%       currData = currData(currData > master.NIDAQ.cutoffVoltage);
      if isfield(master,'debugging') && isfield(master.debugging,'switch') && master.debugging.switch
        master.debugging.currData2 = currData;
      end
      %Adds to sum and number for data
      ndata(sigref) = ndata(sigref) + numel(currData);
      sortdata(sigref) = sortdata(sigref) + sum(currData);
      if isfield(master,'debugging') && isfield(master.debugging,'switch') && master.debugging.switch
        master.debugging.sortdata = sortdata;
        master.debugging.ndata = ndata;
      end
         
      %Increments to next counter increase
      nn = nn+1;
      
      %If this is the last counter increase, stop. Since the code looks
      %forward by 1, the last increase cannot be used.
      if nn == numel(ctrincs) - 1 || nn == numel(ctrincs) + 1 || nn == numel(ctrincs)
         break
      end
 
   end
   
   %Take average
   reference = sortdata(1) / ndata(1);
   signal = sortdata(2) / ndata(2);
   else
       currdata = unsortedData(:,2);
       reference = mean(currdata(currdata > master.NIDAQ.cutoffVoltage));
       signal = reference;
   end
    catch ME
        master.debugging.error = ME;
    end
end

if ~master.NIDAQ.confocal && isfield(master,'debugging') && isfield(master.debugging,'switch') && master.debugging.switch
    if reference == 0 || signal == 0
        master.debugging.unsortedData = unsortedData;
        master.debugging.ctrdiff = ctrdiff;
        master.debugging.cntincs = cntincs;
        error('gave 0')
    end
end

end


