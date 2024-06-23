function NIDAQInitialization
%Initializes NI DAQ for use later

%Instrument dependencies:
%NI DAQ

%Code dependencies: none

%NIDAQInitialization v2.1 9/8/22

global master %#ok<*GVMIS>
global NIDAQ

if ~isfield(master,'notifications'),      master.notifications = true;     end

%Checks if master.NIDAQ.initialized exists in usable form. If not,
%makes said variable false
if ~isfield(master,'NIDAQ'),     master.NIDAQ.initialized = false;      end

if ~isfield(master.NIDAQ,'initialized'),     master.NIDAQ.initialized = false;      end

%Begins initialization if not already initialized
if ~master.NIDAQ.initialized
   
   if master.notifications
      fprintf('Beginning NI DAQ initialization\n')
   end
   
   %If max rate has not already been set, defaults max rate to 1.25e6
   if ~isfield(master.NIDAQ, 'maxrate'),     master.NIDAQ.maxrate = 1.25e6;      end

   if ~isfield(master.NIDAQ, 'removeOutlierValue'),     master.NIDAQ.removeOutlierValue = -Inf;      end

   %Defaults to using the clock
   if ~isfield(master.NIDAQ,'useClock'),     master.NIDAQ.useClock = true;    end
   
   %Defaults to confocal setup
   if ~isfield(master.NIDAQ,'confocal'),     master.NIDAQ.confocal = true;    end
   
   while true
      if isfield(master,'comp')
         aa = master.comp;
         if isstring(aa) || ischar(aa)
            if strcmp(aa,"NV") || strcmp(aa,"NV2") || strcmp(aa,"SMM")
               break
            else
               if master.notifications
                  fprintf('Computer designation must be either "NV", "NV2", or "SMM"\n')
               end
            end
         else
            if master.notifications
               fprintf("Computer designation must be a string\n")
            end
         end
      end
      master.comp = input('Computer designation? "NV", "NV2", or "SMM"\n');
   end
   
   try
      %Connection to daq and addition of inputs
      NIDAQ = daq("ni");
      NIDAQ.Rate = master.NIDAQ.maxrate;
      
      %Adds edge counter, voltage, and clock channels

      %If you are trying to figure out what channels can do what, use the
      %command daqlist to give a table of viable devices. Within that
      %table, there is a DeviceInfo object that contains the information
      %you need (hopefully) within the terminals and subsystems structures

      
      if strcmp(master.comp,"NV")
      master.NIDAQ.counter = addinput(NIDAQ,"Dev1", "ctr2","EdgeCount");  
      master.NIDAQ.analog = addinput(NIDAQ,"Dev1", "ai0","Voltage");
      master.NIDAQ.digital = addinput(NIDAQ,"Dev1", "port0/line1","Digital");
      master.NIDAQ.clock = addclock(NIDAQ,"ScanClock","External","Dev1/PFI12");      
      elseif strcmp(master.comp,"NV2")
         master.NIDAQ.counter = addinput(NIDAQ,"Dev2", "ctr2","EdgeCount");      
         master.NIDAQ.analog = addinput(NIDAQ,"Dev2", "ai0","Voltage");
        master.NIDAQ.clock = addclock(NIDAQ,"ScanClock","External","Dev2/PFI1");
      end
      NIDAQ.Channels(2).TerminalConfig = "SingleEnded"; %Gets voltage measurements reasonable
      
      if master.notifications
         fprintf("NI DAQ initialized\n")
      end

      if strcmp(master.comp,'NV2')
          NIDAQ.ScansAvailableFcn = @storeData;
          %NIDAQ.ErrorOccurredFcn = @daqError;
      end
      

      master.NIDAQ.initialized = true;
      
   catch ME
      if master.notifications
         fprintf('Error connecting to NI DAQ\n')
      end
      rethrow(ME)
   end
   
else %If already initialized
   if master.notifications
      fprintf("NI DAQ already initialized\n")
   end
end

function NIDAQ = storeData(NIDAQ,evt)
%     global testData
    
 newdata= read(NIDAQ,NIDAQ.ScansAvailableFcnCount,"OutputFormat","Matrix");
%  testData = newdata;
 if isempty(newdata)
   return
 end
 ctrdiff = diff(newdata(:,1)); %Difference in number of counts
 newdata(1,:) = []; %Deletes first line for simplicity
 %Add up all the changes in the number of counts where the voltage is
 %less/greater than the cutoff which will be the reference/signal
 ref = sum(ctrdiff(newdata(:,2) <= 1.5));
 sig = sum(ctrdiff(newdata(:,2) > 1.5));


 if ~isempty(NIDAQ.UserData)
     NIDAQ.UserData(end+1,1:2) = [ref sig];
 else
     NIDAQ.UserData(1,1) = ref;
     NIDAQ.UserData(1,2) = sig;
 end
end

    %function NIDAQ = daqError(NIDAQ,evt)
        %disp('error happened here')
        %master.debugging.daqError = evt;
%         exit()
    %end

end


