pyData = tdfread("Overnight correlation with fomblin.txt.");
xax = 1000 + pyData.t;
r = pyData.r;
s = pyData.s;
c = (r-s)./r;
figure (1)
plot(xax,c)
title('Time Domain Contrast')
ylabel('Contrast')
xlabel('Time (ns)')
%%
T = 20e-9;
Fs = 1/T;
L = numel(xax);
Y = fft(contrastFromAverageSR);
P2 = abs(Y/L);
P1 = P2(1:L/2+1);
P1(2:end-1) = 2*P1(2:end-1);
f = Fs/L*(0:(L/2));
P1(1) = [];
f(1) = [];
figure (2)
plot(f./1e6,P1)
title('FFT')
ylabel('Intensity')
xlabel('Frequency (MHz)')

