%Simulation of xy8 dip

%% Parameters
%Spin density per nm^3
rho=4.1;

%Vector of NV depths to simulate
NVDepth = [10,12.5,15]; %nm

%Mid-Peak to Mid-Peak duration of pi flips
tauBounds = [400 800];
tauStepSize = 2;

%Number of pi pulses
XYPerSet = 8;
NSets = 24;

%Gyromagnetic ratio of nucleus
gamma_n = 40.078;%MHz/T       19F=40.078, 13C=10.705, 1H=42.577

%Frequency of peak in ODMR (used to get magnetic field strength)
onaxisfreq=2.286;

%Noise addition
sigma = 0;%Standard deviation for gaussian distributed noise (approximation)

%% Constants and Conversions
mu_0=4*pi*10^-7;
hbar=(6.626*10^-34)/(2*pi);

rho = rho*1e27;%Conversion to m^-3

tau=tauBounds(1):tauStepSize:tauBounds(2);
tau=tau';
tau=tau*10^-9;%Conversion to s

%Total number of pi pulses
N = XYPerSet*NSets;

NVDepth = NVDepth*1e-9;%Conversion to m
NVDepth=NVDepth';

%nuclear gyromagnetic ratio in radians per Tesla per second
gamma_n=gamma_n*2*pi*10^6; %Conversion to radians/(T*s)
gamma_e=1.760859*10^11;

%% Calculations

%Larmor frequency for given nucleus at given magnetic field strength
larmorfreq=2*pi*(10^9)*(2.87-onaxisfreq)*gamma_n/(1.760859*10^11);

%RMS field experienced by the NV
individualNuclearField = (mu_0*hbar*gamma_n)/(4*pi);
NVDepthRelation = (5*pi)./(96.*(NVDepth.^3));
Brms = sqrt(rho.*(individualNuclearField.^2).*NVDepthRelation);

% Creating frequency filter function
shorthandX = (N/2).*(tau.*larmorfreq-pi);
sincFunction = sin(shorthandX)./(shorthandX);
Kfilter = (N.*tau.*sincFunction).^2;

%Signal function at each depth
Signalfunction=zeros(numel(tau),numel(NVDepth));
for jj = 1:numel(NVDepth)
   Signalfunction(:,jj) = exp((-2/pi^2)*(Brms(jj)*gamma_e)^2.*Kfilter);
end

%Add noise
noiseArray = sigma*randn(size(Signalfunction));
Signalfunction = Signalfunction+noiseArray;

%% Deprecated Calculations

% ii=1;
% Brms=zeros(numel(dNV),1);
% while(ii<=numel(dNV))
%     Brms(ii)=sqrt(rho*(((mu_0*hbar*gamma_n/(4*Pi)))^2)*(5*Pi/(96*dNV(ii)*dNV(ii)*...
%         dNV(ii))));
%     ii=ii+1;
% end

% filterParameter=N*tau;
% Kfilter=zeros(numel(tau),1);
% for ii = 1:numel(tau)
%     Kfilter(ii)=(filterParameter(ii)^2)*((sin(0.5*filterParameter(ii)*(larmorfreq-(pi/tau(ii))))/(0.5*filterParameter(ii)*(larmorfreq-(pi/tau(ii)))))^2);
% end

% for ii = 1:numel(tau)
%    for jj = 1:numel(NVDepth)
%       Signalfunction(ii,jj)=exp(-1*2*Brms(jj)*gamma_e*gamma_e*Brms(jj)*Kfilter(ii)/(pi*pi));
%       Signalfunction(ii,jj) = Signalfunction(ii,jj)+ noiseMod*(rand-.5);
%    end
% end

%% Plotting

figure(1);
plot(tau,Signalfunction)
title('Expected NMR dip post-normalization')
depthString = compose("%d nm",round(NVDepth.*1e9));
legend(depthString)
xlabel('Tau (ns)')
ylabel('Relative Contrast')