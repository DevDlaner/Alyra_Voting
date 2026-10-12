// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

// systeme de vote Amelioré:
// je voulais partir sur des nft, mais je simplifie:
//
// Imaginons que l'admin puisse faire un snapshot a un instant T des droits de votes des utilisatuers:
// ca peut etre par la possession de token, ou la valorisation de certaines actions externes...
//
// je vais donc ajouter un "nombre de vote" par utilisateur: un poids...
// l'utilisateur aura le droit de mettre tout ses votes pour une proposition qu'il souhaite appuyer totalement...
// ou les repartir suivant ses choix...
//
// pour "simuler le transfert" de token de droit de vote, je vais ajouter une fonction de transfert de votes entres utilisateurs whitelistés.
//
// je vais aussi remedier au soft lock de passer en start proposing avant d'avoir ajouter un utilisateur, 
// et laisser le droit ouvert jusqu'a l'ouverture des votes: je close l'ajout de voter a ce moment la:
// meme si il est trop tard pour ajouter une proposition, on peut gagner le droit de voter jusqu'a l'ouverture de votes.

// fonctions renommées pour faciliter les test dans l'environement remix:
// l'ordre alphabetique rendait la tache plus difficile.

import "@openzeppelin/contracts/access/Ownable.sol";

contract VotingPlus is Ownable {

    // ----- Types -----
    struct Stat {
        uint nbVoters;
        uint nbVotesGifted;
        uint nbVotesUsed;
    }

    struct Vote {
        uint votedProposalId;
        uint nbVotes;
    }

    struct Voter {
        bool isRegistered;
        uint votingPower;
        Vote[] votes;
    }

    struct Proposal {
        string description;
        uint voteCount;
    }
    enum WorkflowStatus {
        RegisteringVoters,
        ProposalsRegistrationStarted,
        ProposalsRegistrationEnded,
        VotingSessionStarted,
        VotingSessionEnded,
        VotesTallied
    }

    // ----- Variables -----
    // pour les stats (moyenne, minimum de votants, etc...
    Stat public stats;

    // En cas de plusieur votes lancé en meme temps
    string voteName;

    // ces 2 variables sont en private pour "forcer" le passage par mon get et les require...
    mapping(address => Voter) private voters;
    Proposal[] private proposals;

    WorkflowStatus public workflowStatus;
    // j'ai choisis de passer cette variable en private,
    // pour ne permetre l'acces qu'une fois le vote terminé.
    // En accedant a cette variable trop tot, on peut croire que la variable est deja preremplie.
    uint private winningProposalId;

    // ----- Events -----
    event Warning(string message);
    event VoterRegistered(address voterAddress);
    event VoteAllowed(address voterAddress,uint nbVotes);

    event WorkflowStatusChange(
        WorkflowStatus previousStatus,
        WorkflowStatus newStatus
    );

    event ProposalRegistered(uint proposalId);

    event Voted(address voter, uint proposalId, uint votingPower);
    event VoteTransfered(address  voterSender,address _voterReceiver,uint _votingPowerGiven);

    // ----- Modifiers -----
    modifier onlyVoters() {
        require(voters[msg.sender].isRegistered,"You're not whitelisted");
        _;
    }

    // ----- Constructor -----
    constructor() Ownable(msg.sender) {
        workflowStatus = WorkflowStatus.RegisteringVoters;
    }

    // ----- Fonctions -----
    // --- Admin ---
    function step01_addVoter(address _voter,uint _nbVotes) external onlyOwner {
        require(_voter != address(0), "Invalid address");
        require(workflowStatus < WorkflowStatus.VotingSessionStarted,"Voters registration is closed");
        require(!voters[_voter].isRegistered,"Voter already registered");
        require(_nbVotes>=1,"need at least 1 vote power");

        voters[_voter].isRegistered = true;
        voters[_voter].votingPower = _nbVotes;
        stats.nbVoters++; // ici, je suppose qu'on donne les droit de vote en une fois, pour simplifier (grace au require)
        stats.nbVotesGifted +=_nbVotes;
        emit VoterRegistered(_voter);
        emit VoteAllowed(_voter,_nbVotes);
    }

    // - Status -
    function step02_startProposals() external onlyOwner {
        require(workflowStatus == WorkflowStatus.RegisteringVoters,"Voters registration phase is not active");
        require(stats.nbVoters > 0, "No voter yet => softLock incoming");
        _changeWorkflowStatus(WorkflowStatus.ProposalsRegistrationStarted);
    }

    function step04_endProposals() external onlyOwner {
        require(workflowStatus == WorkflowStatus.ProposalsRegistrationStarted,"Proposals registration has not started");
        // vu qu'on peut pas revenir en arriere, je bloque la fin des registration si aucune proposition...
        require(proposals.length > 0, "No proposal registered");

        _changeWorkflowStatus(WorkflowStatus.ProposalsRegistrationEnded);
    }


    function step06_startVoting() external onlyOwner {
        require(workflowStatus == WorkflowStatus.ProposalsRegistrationEnded,"Proposals registration is not ended");

        // doublons, mais en cas d'editions des proposal en externe entre la fin des propositions, et le debut du vote...
        // dans ce cadre precis, pas utile (je test deja a la fin des votes), mais je prefere le mettre au cas ou un jour je veuille reutiliser le code...
        require(proposals.length > 0, "No proposal registered");

        _changeWorkflowStatus(WorkflowStatus.VotingSessionStarted);
    }


    function step08_endVoting() external onlyOwner {
        require(workflowStatus == WorkflowStatus.VotingSessionStarted,"Voting session has not started");

        if (stats.nbVotesUsed==0){
            emit Warning("Vote closed without any vote");
        }

        _changeWorkflowStatus(WorkflowStatus.VotingSessionEnded);
    }

    // - décompte final -
    function step09_tallyVotes() external onlyOwner {
        require(workflowStatus == WorkflowStatus.VotingSessionEnded,"Voting session is not ended");

        uint highestVoteCount = proposals[0].voteCount;
        winningProposalId = 0;

        // En cas d'égalité, on conserve la premiere proposition...
        // fonctionne en cas de 0 votes du coup...
        for (uint i = 1; i < proposals.length; i++) {
            if (proposals[i].voteCount > highestVoteCount) {
                highestVoteCount = proposals[i].voteCount;
                winningProposalId = i;
            }
        }

        _changeWorkflowStatus(WorkflowStatus.VotesTallied);
    }

    // --- Voters ---
    function step03_addProposal(string memory _description) external onlyVoters {
        require(bytes(_description).length > 0, "Invalid proposal");
        require(workflowStatus == WorkflowStatus.ProposalsRegistrationStarted,"You can't add proposal right now");

        proposals.push(Proposal(_description,0));
        emit ProposalRegistered(proposals.length-1);
    }
    
    function step05_giveVote(address _voterAddress, uint _votingPowerGiven) external onlyVoters {

        require(workflowStatus < WorkflowStatus.VotingSessionEnded,"This vote is finished");

        require(_voterAddress != msg.sender,"Cannot transfer voting power to yourself");

        require(voters[msg.sender].isRegistered,"Giver is not whitelisted");
        require(voters[_voterAddress].isRegistered,"Receiver is not whitelisted");

        require(_votingPowerGiven > 0,"Voting power must be greater than zero");
        require(voters[msg.sender].votingPower>0,"Voter has no powerVoting left");
        require(voters[msg.sender].votingPower>=_votingPowerGiven,"Voter has not enough powerVoting left");

        voters[msg.sender].votingPower-=_votingPowerGiven;
        voters[_voterAddress].votingPower+=_votingPowerGiven;
        emit VoteTransfered(msg.sender, _voterAddress, _votingPowerGiven);
    }

    function step07_vote(uint _voteId, uint _votingPower) external onlyVoters {
        require(workflowStatus == WorkflowStatus.VotingSessionStarted,"This vote isn't active right now");
        require(voters[msg.sender].votingPower>0,"Voter has no powerVoting left");
        require(voters[msg.sender].votingPower>=_votingPower,"Voter has not enough powerVoting left");
        require(_voteId <proposals.length, "Invalid vote (proposal ID too high)");

        proposals[_voteId].voteCount+=_votingPower;
        voters[msg.sender].votingPower-=_votingPower;
        voters[msg.sender].votes.push(Vote(_voteId,_votingPower));
        stats.nbVotesUsed += _votingPower;
        emit Voted(msg.sender, _voteId, _votingPower);
    }

    // ----- Fonctions internes -----
    function _changeWorkflowStatus(WorkflowStatus _newStatus) internal {
        WorkflowStatus previousStatus = workflowStatus;
        workflowStatus = _newStatus;

        emit WorkflowStatusChange(previousStatus, _newStatus);
    }

    // ----- Getters -----
    function getVoter(address _voter) external view returns (Voter memory) { 
        require(voters[_voter].isRegistered, "Voter not registered");
        return voters[_voter];
    }
    function getVoterVotes(address _voter) external view returns (Vote[] memory) {
        require(voters[_voter].isRegistered, "Voter not registered");
        return voters[_voter].votes;
    }
    function getProposals() external view returns (Proposal[] memory){
        require(proposals.length>0,"No proposal yet");
        return proposals;
    }
    function getWinner() external  view returns (Proposal memory) {
        require(workflowStatus == WorkflowStatus.VotesTallied,"Votes not counted yet");
        return proposals[winningProposalId];
    }
    function getWinningProposalId() external view returns (uint) {
        require(workflowStatus == WorkflowStatus.VotesTallied,"Votes not counted yet");

        return winningProposalId;
    }
}