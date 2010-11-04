require 'lib/voting'

class TwoPCAgent < VotingAgent
  # 2pc is a specialization of voting:
  # * ballots describe transactions
  # * voting is Y/N.  A single N vote should cause abort.
  def state
    super
  end

end


class TwoPCMaster < VotingMaster
  # 2pc is a specialization of voting:
  # * ballots describe transactions
  # * voting is Y/N.  A single N vote should cause abort.
  def state
    super
    table :xact, ['xid', 'data'], ['status']
    scratch :request_commit, ['xid'], ['data']
  end
  
  declare 
  def boots
    xact <= request_commit.map{|r| [r.xid, r.data, 'prepare'] }
    begin_vote <= request_commit.map{|r| [r.xid, r.data] }
  end

  declare
  def panic_or_rejoice
    decide = join([xact, vote_status], [xact.xid, vote_status.id])
    xact <+ decide.map do |x, s|
      [x.xid, x.data, "abort"] if s.response == "N"
    end

    xact <- decide.map do |x, s|
      x if s.response == "N"
    end

    xact <+ decide.map do |x, s|
      [x.xid, x.data, "commit"] if s.response == "Y"
    end
  end
  
end

class Monotonic2PCMaster < VotingMaster
  def initialize(i, p, o)
    super(i, p, o)
    xact_order << ['prepare', 0]
    xact_order << ['commit', 1]
    xact_order << ['abort', 2]
  end
  def state
    super
    table :xact_order, ['status'], ['ordinal']
    table :xact_final, ['xid', 'ordinal']
    scratch :xact, ['xid', 'data', 'status']
    table :xact_accum, ['xid', 'data', 'status']
    scratch :request_commit, ['xid'], ['data']
    scratch :sj, ['xid', 'data', 'status', 'ordinal']
  end
  
  declare 
  def boots
    xact_accum <= request_commit.map{|r| [r.xid, r.data, 'prepare'] }
    begin_vote <= request_commit.map{|r| [r.xid, r.data] }
  end

  declare
  def panic_or_rejoice
    decide = join([xact_accum, vote_status], [xact_accum.xid, vote_status.id])
    xact_accum <= decide.map do |x, s|
      [x.xid, x.data, "abort"] if s.response == "N"
    end

    xact_accum <= decide.map do |x, s|
      [x.xid, x.data, "commit"] if s.response == "Y"
    end
  end
  
  declare
  def twopc_status
    sj <= join([xact_accum, xact_order], [xact_accum.status, xact_order.status]).map do |x,o|
      [x.xid, x.data, x.status, o.ordinal]
    end
    xact_final <= sj.group([sj.xid], max(sj.ordinal))
    xact <= join( [sj, xact_final], [sj.ordinal, xact_final.ordinal]).map do |s, x|
      [s.xid, s.data, s.status]
    end
  end
end