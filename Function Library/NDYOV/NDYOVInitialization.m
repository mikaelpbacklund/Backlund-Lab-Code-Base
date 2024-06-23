function NDYOVInitialization
%Initializes ND:YOV laser for later use

%Instrument dependencies:
%ND YOV laser on NV computer

%Code dependencies: 
%InitializationCheck
%NDYOVEquilibrium
%NDYOVSwitch*
%NDYOVSetPower*

%* indicates only required if corresponding setting already present

%NDYOVInitialization v2.0 4/20/22

global master %#ok<*GVMIS> 
global NDYOV

if ~isfield(master,'notification'),    master.notifications = true;     end

%Note: laser can sometimes take a while to interpret then respond to
%commands. I am not sure why but these commands seem to work well to
%mitigate any delay issues

%Checks if master.NDYOV.initialized exists in usable form. If not,
%makes said variable false
iscorrect = false;
if isfield(master,'NDYOV')
   if isfield(master.NDYOV,'initialized')
      if isscalar(master.NDYOV.initialized) && ~isstring(master.NDYOV.initialized)
         iscorrect =true;
      end
   end
end
if ~iscorrect
   master.NDYOV.initialized = false;
end

%If not already initialized, begin initialization
if ~master.NDYOV.initialized
    
    if master.notifications
        fprintf('Beginning Nd:YOV laser initialization\n')
    end
   
    %If not already present, sets tolerance for laser to 0.005 Watts
   if ~isfield(master.NDYOV,'tolerance'),    master.NDYOV.tolerance = 0.005;      end
   
   %If not already present, sets waitforequilibrium to false which lets
   %matlab continue to operate while the laser is changing power
   if ~isfield(master.NDYOV,'waitforequilibrium'),    master.NDYOV.waitforequilibrium = false;     end
   
   %If not already present, sets offwhencleaned to true which turns the
   %laser off when the CleanUp command is used
   if ~isfield(master.NDYOV,'offwhencleaned'),     master.NDYOV.offwhencleaned = true;    end
   
   try      
      %Establishes connection with laser on virtual port 10
      NDYOV = serialport("COM10",19200);
      configureTerminator(NDYOV,"CR")
      
      writeline(NDYOV,"SHUTTER?")
      shutterstatus = convertStringsToChars(readline(NDYOV));
      
      shutterstatus(1:8)=[];
      if strcmp(shutterstatus,"CLOSED")
         error('Shutter is closed')
      end
      
      while true
         
         %Queries laser as to on/off status
          writeline(NDYOV,"OPMODE?")
         currentstatus = convertStringsToChars(readline(NDYOV));
         
         %If taking away 7 characters gives a valid status, continue
         try
             currentstatus(1:7)=[];
         catch      
            currentstatus = "failed";
         end
         
         %When currentstatus is a viable option, changes format to match
         %that of master, otherwise waits half a second for laser to
         %respond
         switch currentstatus
            case 'OFF'
               currentstatus = "off";
               break
            case 'ON'
               currentstatus = "on";
               break
            case 'IDLE'
               currentstatus = "idle";
               break
            otherwise
               pause(.1)
         end

      end
      
      %sets initialization status to true to allow other functions to run
      master.NDYOV.initialized = true;
      
      %If switch is set, runs function to switch on/off, otherwise sets
      %current value as the settings value
      if ~isfield(master.NDYOV,'switch')
         master.NDYOV.switch = currentstatus;
      elseif ~strcmp(master.NDYOV.switch,currentstatus)
         NDYOVSwitch         
      end
      
      %Queries current power setting of laser
      while true
         
          writeline(NDYOV,"POWER SET?")
         setpower = convertStringsToChars(readline(NDYOV));
         
         %If taking away 10 characters gives a number, stop loop
         try
            setpower(1:10) = [];
            setpower = str2double(setpower);
            break
         catch
            pause(.1)
         end
         
      end
      
      %If setpower is already present, run power set function, otherwise
      %change setting value to current actual value
      if ~isfield(master.NDYOV,'setpower')
         master.NDYOV.setpower =  setpower;
      elseif master.NDYOV.setpower ~= setpower
         NDYOVSetPower        
      end
          
      %Queries current actual power of laser
      while true
         
          writeline(NDYOV,"POWER?")
         master.NDYOV.power = convertStringsToChars(readline(NDYOV));
         
         %If taking away 6 characters gives a number, stop loop
         try
            master.NDYOV.power(1:6) = [];
            master.NDYOV.power = str2double(master.NDYOV.power);
            break
         catch
            pause(.1)
         end         
         
      end
      
      %Checks if laser is equilibrated if waitforequilibrium is true
      NDYOVEquilibrium
      
   catch ME
      master.NDYOV.initialized = false;
      try
         clear global NDYOV
      catch
      end
      rethrow(ME)
   end
   
   if master.notifications
   fprintf('ND YOV laser successfully initialized\n')
   end

else
    if master.notifications
   fprintf("ND YOV laser already initialized\n")
    end
end

end



