%% Neurodata Without Borders: Neurophysiology (NWB:N), Extracellular Electrophysiology Tutorial
% How to write ecephys data to an NWB file using matnwb.
% 
%  author: Ben Dichter
%  contact: ben.dichter@gmail.com
%  last edited: Oct 9, 2018

%% NWB file
% All contents get added to the NWB file, which is created with the
% following command

date = datetime(2018, 3, 1, 12, 0, 0);
session_start_time = datetime(date,'Format','yyyy-MM-dd''T''HH:mm:SSZZ',...
    'TimeZone','local');
nwb = nwbfile( 'source', 'acquired on rig2', ...
    'session_description', 'a test NWB File', ...
    'identifier', 'mouse004_day4', ...
    'session_start_time', session_start_time);

%%
% You can check the contents by displaying the nwbfile object
disp(nwb);

%% Data dependencies
% The data needs to be added to nwb in a specific order, which is specified
% by the data dependencies in the schema. The data dependencies for LFP are
% illustrated in the following diagram. In order to write LFP, you need to 
% specify what electrodes it came from. To do that, you first need to 
% construct an electrode table. 
%%
% 
% <<ecephys_data_deps.png>>
% 

%% Electrode Table
% Electrode tables hold the position and group information about each 
% electrode and the brain region and filtering. Groups organize electrodes 
% within a single device. Devices can have 1 or more groups. In this example, 
% we have 2 devices that each only have a single group.

device_labels = {'a','a','a','a','a','b','b','b','b','b'};

udevice_labels = unique(device_labels, 'stable');

variables = {'id', 'x', 'y', 'z', 'imp', 'location', 'filtering', ...
    'group', 'group_name'};
for i_device = 1:length(udevice_labels)
    device_label = udevice_labels{i_device};
    
    nwb.general_devices.set(device_label,...
        types.core.Device());
    
    nwb.general_extracellular_ephys.set(device_label,...
        types.core.ElectrodeGroup(...
        'description', 'a test ElectrodeGroup', ...
        'location', 'unknown', ...
        'device', types.untyped.SoftLink(['/general/devices/' device_label])));
    
    ov = types.untyped.ObjectView(['/general/extracellular_ephys/' device_label]);
    
    elec_nums = find(strcmp(device_labels, device_label));
    for i_elec = 1:length(elec_nums)
        elec_num = elec_nums(i_elec);
        if i_device == 1 && i_elec == 1
            tbl = table(int64(1), NaN, NaN, NaN, NaN, {'CA1'}, {'filtering'}...
                , ov, {'electrode_group'},'VariableNames', variables);
        else
            tbl = [tbl; {int64(elec_num), NaN, NaN, NaN, NaN,...
                'CA1', 'filtering', ov, 'electrode_group'}];
        end
    end        
end
%%
% add the |DynamicTable| object to the NWB file using the name |'electrodes'| (not flexible)

tbl.Properties.Description = 'my description';

electrode_table = util.table2nwb(tbl);
nwb.general_extracellular_ephys.set('electrodes', electrode_table);

%% LFP
% In order to write LFP, you need to construct a region view of the electrode 
% table to link the signal to the electrodes that generated them. You must do
% this even if the signal is from all of the electrodes. Here we will create
% a reference that includes all electrodes. Then we will randomly generate a
% signal 1000 timepoints long from 10 channels

ov = types.untyped.ObjectView('/general/extracellular_ephys/electrodes');

electrode_table_region = types.core.DynamicTableRegion('table', ov, ...
    'description', 'all electrodes',...
    'data', [1 height(tbl)]');

%%
% once you have the |ElectrodeTableRegion| object, you can create an
% ElectricalSeries object to hold your LFP data. Here is an example using
% starting_time and rate.

electrical_series = types.core.ElectricalSeries(...
    'starting_time', 0.0, ... % seconds
    'starting_time_rate', 200., ... % Hz
    'data', randn(10, 1000),...
    'electrodes', electrode_table_region,...
    'data_unit','V');

nwb.acquisition.set('ECoG', electrical_series);
%%
% You can also specify time using timestamps. This is particularly useful if
% the timestamps are not evenly sampled. In this case, the electrical series
% constructor will look like this

electrical_series = types.core.ElectricalSeries(...
    'timestamps', (1:1000)/200, ...
    'starting_time_rate', 200., ... % Hz
    'data', randn(10, 1000),...
    'electrodes', electrode_table_region,...
    'data_unit','V');

%% Trials
% You can store trial information in the trials table

trials = types.core.TimeIntervals( ...
    'colnames', {'correct','start_time','stop_time'},...
    'description', 'trial data and properties', ...
    'id', types.core.ElementIdentifiers('data', 1:3),...
    'start_time', types.core.VectorData('data', [.1, 1.5, 2.5],...
        'description','hi'),...
    'stop_time', types.core.VectorData('data', [1., 2., 3.],...
        'description','hi'),...
    'correct', types.core.VectorData('data', [false,true,false],...
        'description','my description'));

nwb.intervals.set('trials', trials);

%%
% |colnames| is flexible - it can store any column names and the entries can
% be any data type, which allows you to store any information you need about 
% trials. The units table stores information about cells and is created with
% an analogous workflow.

%% Processing Modules
% Measurements go in |acquisition| and subject or session data goes in
% |general|, but if you have the result of an analysis, e.g. spike times,
% you need to store this in a processing module. Here we make a processing
% module called "cellular"

cell_mod = types.core.ProcessingModule('description', 'a test module');

%% Spikes
% There are two different ways of storing spikes (aka action potentials),
% |Clustering| and |UnitTimes|. |Clustering| is more strightforward, and is used to mark
% measured threshold crossings that are spike-sorted into different clusters,
% indicating that they are believed to come from different neurons. The
% advantage of this structure is that it is easy to write data via a stream
% and it is easy to query based on time window (since the timestamps are 
% ordered).

spike_times = [0.1, 0.21, 0.34, 0.36, 0.4, 0.43, 0.5, 0.61, 0.66, 0.69];
cluster_ids = [0, 0, 1, 1, 2, 2, 0, 0, 1, 1];

clustering = types.core.Clustering( ...
    'description', 'my_description',...
    'peak_over_rms',[1,2,3],...
    'times', spike_times, ...
    'num', cluster_ids);

cell_mod.nwbdatainterface.set('clustering',clustering);
nwb.processing.set('cellular', cell_mod);

%%
% The other structure is within the |units| table, which is organized by cell instead of
% by time. The advantage of |units| is that it is more
% parallel-friendly. It is easier to split the computation of by cells are
% read/write in parallel, distributing the cells across the cores of your
% computation network.
%%
% 
% <<UnitTimes.png>>
% 
%%

[spike_times_vector, spike_times_index] = util.create_spike_times(cluster_ids, spike_times);
nwb.units = types.core.Units('colnames',{'spike_times','spike_times_index'},...
    'description','units table',...
    'id', types.core.ElementIdentifiers('data',1:length(spike_times_index.data)));
nwb.units.spike_times = spike_times_vector;
nwb.units.spike_times_index = spike_times_index;


%% Writing the file
% Once you have added all of the data types you want to a file, you can save
% it with the following command

nwbExport(nwb, 'ecephys_tutorial.nwb')

%% Reading the file
% load an NWB file object into memory with

nwb2 = nwbRead('ecephys_tutorial.nwb');

%% Reading data
% Note that |nwbRead| does *not* load all of the dataset contained 
% within the file. matnwb automatically supports "lazy read" which means
% you only read data to memory when you need it, and only read the data you
% need. Notice the command

disp(nwb2.acquisition.get('ECoG').data)

%%
% returns a DataStub object and does not output the values contained in 
% |data|. To get these values, run

data = nwb2.acquisition.get('ECoG').data.load;
disp(data(1:10, 1:10));

%%
% Loading all of the data is not a problem for this small
% dataset, but it can be a problem when dealing with real data that can be
% several GBs or even TBs per session. In these cases you can load a specific secion of
% data. For instance, here is how you would load data starting at the index
% (1,1) and read 10 rows and 20 columns of data

nwb2.acquisition.get('ECoG').data.load([1,1], [10,20])

%%
% run |doc('types.untyped.DataStub')| for more details on manual partial
% loading. There are several convenience functions that make common data
% loading patterns easier. The following convenience function loads data 
% for all trials

% data from .05 seconds before and half a second after start of each trial
window = [-.05, 0.5]; % seconds

% only data where the attribute 'correct' == 0
conditions = containers.Map('correct', 0);

% get ECoG data
timeseries = nwb2.acquisition.get('ECoG');

[trial_data, tt] = util.loadTrialAlignedTimeSeriesData(nwb2, ...
    timeseries, window, conditions);

% plot data from the first electrode for those two trials (it's just noise in this example)
plot(tt, squeeze(trial_data(:,1,:)))
xlabel('time (seconds)')
ylabel(['ECoG (' timeseries.data_unit ')'])

%% Reading UnitTimes (RegionViews)
% |UnitTimes| uses RegionViews to indicate which spikes belong to which cell.
% The structure is split up into 3 datasets (see Spikes secion):
my_spike_times = nwb.units.spike_times;
%%
% To get the data for cell 1, first determine the uid that equals 1.
select = nwb.units.id.data == 1
%%
% Then select the corresponding spike_times_index element
my_index = nwb.units.spike_times_index.data(select)
%%
% Finally, access the data that the view points to using |refresh|
my_index.refresh(nwb)
