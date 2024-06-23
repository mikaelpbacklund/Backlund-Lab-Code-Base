%Creates object
srsRF = RF_generator;

%Connects to instrument
srsRF = connect(srsRF,'RF_generator_config');

%Turns RF on
srsRF = toggle(srsRF,'on');

%Check if RF turned on
srsRF = toggleQuery(srsRF);
turnedOn = strcmp(srsRF.status,'on');%Example of usage

%To query/set any property, use query### and set### where ### is the
%property in question
%e.g.
srsRF = setFrequency(srsRF,2.87);
srsRF = queryFrequency(srsRF);
%Query sets the internal property of the object to the read out status from
%the instrument. To pull that property directly, do as follows:
freq = srsRF.frequency;
%RFgen instrument properties:
%frequency
%amplitude
%modulationToggle
%modulationType
%modulationWaveform

%Closes connection and deletes object
delete(srsRF)