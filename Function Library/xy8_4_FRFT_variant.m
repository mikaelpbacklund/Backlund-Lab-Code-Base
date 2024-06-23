global master

%Load pulse sequence on the GUI to make things easy
%additionally, load all instruments (DAQ, pulse blaster, stage, RF)

%These are the pulse addresses you need to identify that you want to
%change
scanAddresses = [(3:2:67)+1,(75:2:139)+2];
npulses_to_scan = length(scanAddresses);



% taustart = 300;
% tauend = 600;
npoints = 21;
pipulseduration = 26;

delaySweep = linspace(100,300,npoints);

nu0start = 1.3e6;%1/(2*taustart*1e-9);
nu0end = 1.3000000001e6;%1/(2*tauend*1e-9);
nu0_vec = linspace(nu0start,nu0end,npoints);
q = (600e3)/(9.6e-6);

%What values you want the pulses above to take
%The first values are for the first pulse address, the second for the
%second address
scanValues = cell(1,npulses_to_scan);
for ii = 1:npulses_to_scan
    
    currpulseno = mod(ii,33);
    
    if currpulseno==1
        scanValues{ii} = round(nu0_vec/2/q.*(sqrt(1 + q./nu0_vec.^2)-1)*1e9 - 3/4*pipulseduration);
    elseif (currpulseno>=2)&&(currpulseno<=32)
        scanValues{ii} = round(nu0_vec/2/q.*(sqrt(1 + 2*q*(currpulseno-1/2)./nu0_vec.^2)-...
            sqrt(1 + 2*q*(currpulseno-3/2)./nu0_vec.^2))*1e9 - pipulseduration);
    else
        scanValues{ii} = round(nu0_vec/2/q.*(sqrt(1 + 2*q*(32)./nu0_vec.^2)-...
            sqrt(1 + 2*q*(32-1/2)./nu0_vec.^2))*1e9 - 3/4*pipulseduration);
    end

end
scanValues = [delaySweep,scanValues(1:33),delaySweep,scanValues(34:end)];
scanAddresses = [2,(3:2:67)+1,75,(75:2:139)+2];
% scanAddresses = [1,(3:2:67)+1,74,(75:2:139)+2];

%Number of iterations to do
nIterations = 50;

%Runs a stage optimization then sets the current time as the most recent
%time an optimization was run
stageOptimization
lastOptTime = datetime;

%Preallocation
myDataIterations = zeros(1,numel(scanValues{1}));
% myDataSum = myDataIterations;
bigSig = zeros(1,numel(scanValues{1}));
bigRef = zeros(1,numel(scanValues{1}));

for nIt = 1:nIterations %Each iteration
   nIt
   for dataPoint = 1:numel(scanValues{1}) %Each data point in the scan
      
      
      if datetime-lastOptTime > duration(0,5,0)%Check if last optimization was over 5 mins ago
         %Runs stage optimization. Use GUI to set settings for optimization
         %process
         stageOptimization
         
         lastOptTime = datetime;%Sets new time for last optimization
      end
      
      %This changes the duration of each specified address
      for nAddress = 1:numel(scanAddresses)
         master.PB.sequence(scanAddresses(nAddress)).duration = scanValues{nAddress}(dataPoint);
      end
      
      %Sets the new pulse blaster sequence
      PBFinalize
      
      %Runs the pulse sequence and gets the data
      [sig,ref] = PBRun;
      
      bigSig(dataPoint) = bigSig(dataPoint) + sig;
      bigRef(dataPoint) = bigRef(dataPoint) + ref;
%       myDataSum(dataPoint) = myDataSum(dataPoint) + (ref-sig)/ref;
      myDataIterations(dataPoint) = myDataIterations(dataPoint) + 1;
      
      dataToPresent = (bigRef-bigSig)./bigRef;%myDataSum ./ myDataIterations;%Finds the current average for all data points
      dataToPresent(isnan(dataToPresent)) = 0;%Divide by 0 replacement
      
      plot(delaySweep,dataToPresent)
      set(gcf,'position',[680   358   560   420])
   end
   
   
end

