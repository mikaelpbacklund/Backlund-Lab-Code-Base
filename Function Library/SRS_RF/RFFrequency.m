function RFFrequency
%Changes RF frequency for SRS RF generator

%Instrument dependencies:
%SRS RF generator

%Code dependencies: 
%InitializationCheck
%RFInitialization

%RFFrequency v2.0 4/19/22

global RF %#ok<*GVMIS> 
global master

%Checks if RF generator has been initialized
InitializationCheck('RF')

%Queries instrument as to current frequency
fprintf(RF,'FREQ? MHz');
currfreq = str2double(fscanf(RF))/1000;
setfreq = master.RF.frequency;

%Compares current status to setting then sends frequency command to RF
%generator followed by printing status a message
if currfreq == setfreq
   if master.notifications
      fprintf('RF frequency already %.2f\n',setfreq)
   end
else
   if .00095 < setfreq && setfreq <= 4
      if master.notifications
         fprintf('RF frequency set to %f GHz\n',setfreq)
      end
      setfreq = setfreq*1000;
      fprintf(RF,['FREQ ',num2str(setfreq),' MHz']);
   else
      if master.notifications
         fprintf("Frequency must be between .00095 and 4 GHz. Frequency not changed.\n")
      end
   end
end

end
