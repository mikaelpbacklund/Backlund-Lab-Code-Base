function RFAmplitude
%Changes RF amplitude for SRS RF generator

%Instrument dependencies:
%SRS RF generator

%Code dependencies:
%InitializationCheck
%RFInitialization

%RFAmplitude v2.0 4/19/22

global RF %#ok<*GVMIS>
global master 

%Checks if RF generator has been initialized
InitializationCheck('RF')

%Queries instrument as to current frequency
fprintf(RF,'AMPR?');
curramp = str2double(fscanf(RF));
setamp = master.RF.amplitude;

%Compares current status to setting then sends amplitude command to RF
%generator followed by printing status a message
if curramp == setamp
   if master.notifications
      fprintf('RF amplitude already %.1f dBm\n',setamp)
   end
else
   if -47 <= setamp && setamp <= 13
      fprintf(RF, 'AMPR %d', setamp);
      if master.notifications
         fprintf('RF amplitude set to %.1f dBm\n', setamp)
      end
   else
      if master.notifications
         fprintf("RF amplitude must be between -47 and 13 dBm. Amplitude not changed.\n")
      end
   end
end

end


