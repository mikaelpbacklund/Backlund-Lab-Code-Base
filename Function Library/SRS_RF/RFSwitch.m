function RFSwitch
%Turns SRS RF generator on/off

%Instrument dependencies:
%SRS RF generator

%Code dependencies:
%InitializationCheck
%RFInitialization

%RFSwitch v2.0 4/19/22

global RF %#ok<*GVMIS>
global master

%Checks if RF generator has been initialized
InitializationCheck('RF')

%Queries instrument as to on/off status
fprintf(RF, 'ENBR?');
ison = fscanf(RF);
if strcmp(ison(1),'0')
    ison = false;
else
    ison = true;
end

%Compares current status to setting then sends on/off command to RF
%generator followed by printing status a message
turnon = strcmp(master.RF.switch,"on");
if ison == turnon
   if master.notifications
      fprintf('RF already %s\n',master.RF.switch)
   end
elseif turnon
   fprintf(RF, 'ENBR 1');
   if master.notifications
      fprintf('RF switched on\n')
   end
else
   fprintf(RF, 'ENBR 0');
   if master.notifications
      fprintf('RF switched off\n')
   end
end

end

