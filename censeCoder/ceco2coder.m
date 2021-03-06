function [config, store, obs] = ceco2coder(config, setting, data)                
% ceco2coder CODER step of the expLanes experiment censeCoder                    
%    [config, store, obs] = ceco2coder(config, setting, data)                    
%      - config : expLanes configuration state                                   
%      - setting   : set of factors to be evaluated                              
%      - data   : processing data stored during the previous step                
%      -- store  : processing data to be saved for the other steps               
%      -- obs    : observations to be saved for analysis                         
                                                                                 
% Copyright: felix                                                               
% Date: 20-Apr-2017                                                              
                                                                                 
% Set behavior for debug mode                                                    
if nargin==0, censeCoder('do', 2, 'mask', {}); return; else store=[]; obs=[]; end
           
addpath(genpath('util'));

if ~setting.quant
    warning('Skipping ''coding'' step: no qauntization is applied, Huffman encoding cannot be applied.');
    % Store
    store.X_desc = data.X_desc;
    % Observations
    obs.code_len = [];
    obs.bitrate = [];
    return;
end

sr = 44100;
%% Analysis window definition
if strcmp(setting.desc, 'mel')
    l_frame = 1024;
    l_hop = 0.5*l_frame;
    n_fps = 1+(sr-l_frame)/l_hop; % Number of frames per second with base settings
    if setting.fps % 0 means none
        n_avg = round(n_fps/setting.fps); % Number of consecutive frames to average into one
        n_fps = n_fps/n_avg; % Number of frames per second with custom settings
    else
        n_fps = 1+(sr-l_frame)/l_hop; % Number of frames per second with base settings
    end
elseif strcmp(setting.desc, 'tob')
    l_frame = (round(setting.toblen*sr)-mod(round(setting.toblen*sr), 2)); % Approximately 125ms, "fast" Leq
    l_hop = setting.tobhop*l_frame;
    n_fps = 1+(sr-l_frame)/l_hop;
end

%% Reformatting of x_mel
X_desc_mat = 0;
for ind_fold = 1:length(data.X_desc)
    for ind_file = 1:length(data.X_desc{ind_fold})
        X_desc_mat(1:size(data.X_desc{ind_fold}{ind_file}, 1), end+1:end+size(data.X_desc{ind_fold}{ind_file}, 2)) = data.X_desc{ind_fold}{ind_file};
    end
end

%% 10-minutes frames encoding
l_frame = ceil(60*setting.textframe*n_fps); % length of a texture frame in windows
n_frames = ceil(size(X_desc_mat, 2)/l_frame);
for ind_frame = 1:n_frames
    disp(['Encoding: Processing frame ' num2str(ind_frame) ' of ' num2str(n_frames) '...']);
    %% Frames
    X_frame = X_desc_mat(:, (ind_frame-1)*l_frame+1:min(ind_frame*l_frame, end))'; % Transpose to group by features rather than time windows when reshaping to vector
    X_frame = X_frame(:); % Vector reformatting
    %% Delta compression
    X_delta = delta_enc(X_frame);
    %% Huffman encoding
    switch setting.dictgen
        case 'local'
            [symbol, prob] = huff_dict(X_delta, 'sort'); % DdP
            dict{ind_frame} = huffmandict(symbol, prob, 2, setting.htreealg); % Tree generation
            X_huff{ind_frame} = huffmanenco(X_delta, dict{ind_frame});
            huff_len(ind_frame) = length(X_huff{ind_frame}); % Workaround to allow correct decoding of the last byte, needed because the huffman code is not necessarily a multiple of 8
            code_len(ind_frame) = huff_len(ind_frame);
            for ind_del = 1:size(dict{ind_frame}, 1) % Size of local dictionnary
                code_len(ind_frame) = code_len(ind_frame) + 2*(setting.quant) + length(dict{ind_frame}{ind_del, 2});
            end
        case 'global'
            if ind_frame == 1
                X_desc_all = X_desc_mat';
                X_desc_all = X_desc_all(:);
                X_delta_all = delta_enc(X_desc_all);
                [symbol, prob] = huff_dict(X_delta_all, 'unique', setting.quant); % DdP
                dict = huffmandict(symbol, prob, 2, setting.htreealg); % Tree generation
                save('../embedded/matlab/dict.mat', 'dict');
                clear X_desc_all X_delta_all;
            end
            X_huff{ind_frame} = huffmanenco(X_delta, dict);
            huff_len(ind_frame) = length(X_huff{ind_frame}); % Workaround to allow correct decoding of the last byte, needed because the huffman code is not necessarily a multiple of 8
            code_len(ind_frame) = huff_len(ind_frame);
    end
    X_huff{ind_frame} = bin2dec(reshape(num2str([X_huff{ind_frame}(1:end-mod(end, 8)); X_huff{ind_frame}(end-mod(end, 8)+1:end); zeros(8-mod(length(X_huff{ind_frame}), 8), 1)]), 8, [])');
end
% bitrate = sum(code_len)/length(X_huff)/setting.textframe/60;
bitrate = code_len*n_fps/l_frame;
if strcmp(setting.dataset, 'urbansound8k'); bitrate = bitrate(1:end-1); end % Last frame is incomplete and adds a bias

%% Outputs
% Store
store.X_huff = X_huff;
store.dict = dict;
store.huff_len = huff_len;
if strcmp(setting.desc, 'mel')
    if setting.fps; store.n_frames_avg = data.n_frames_avg; end
end
if setting.quant; store.q_norm = data.q_norm; end
store.n_frames = data.n_frames;
if strcmp(setting.dataset, 'speech_mod'); store.wav_name = data.wav_name; end

% Observations
obs.code_len = code_len;
obs.bitrate = bitrate;
