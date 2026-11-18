using System;

namespace Frostpane
{
    internal sealed partial class SnowScene
    {
        internal const double ChopBeat = .68;

        private bool CanChop(WinterTree tree)
        {
            return tree!=null && Trees.Contains(tree) && tree.Support==floor && !tree.Hidden &&
                   tree!=draggedTree && (draggedDecoration==null || draggedDecoration.Tree!=tree) && !IsLeaving(tree);
        }

        private WinterTree FindTimber(WinterVisitor yeti)
        {
            WinterTree best=null;
            double nearest=double.MaxValue;
            foreach (WinterTree tree in Trees) {
                double distance=Math.Abs(tree.X-yeti.X);
                if (distance>=nearest || !CanChop(tree)) continue;
                bool claimed=false;
                foreach (WinterVisitor other in Visitors)
                    if (other!=yeti && other.Timber==tree) {claimed=true;break;}
                if (!claimed) {best=tree;nearest=distance;}
            }
            return best;
        }

        private Snowman FindYetiFriend(WinterVisitor yeti)
        {
            Snowman best=null;
            double nearest=double.MaxValue;
            foreach (Snowman m in Snowmen) {
                double distance=Math.Abs(yeti.X-m.X)+Math.Abs(yeti.Y-m.Y)*.17;
                if (!m.Held && distance<nearest) {best=m;nearest=distance;}
            }
            return best;
        }

        private bool StepYeti(WinterVisitor v,double dt,double pacedDt)
        {
            if (v.Timber!=null && !CanChop(v.Timber)) {
                v.Timber=null;v.Chops=0;v.Wait=0;v.Met=false;
            }
            if (!v.Met) {
                if (v.Timber==null) v.Timber=FindTimber(v);
                if (v.Timber!=null) v.Friend=null;
                else if (v.Friend==null || v.Friend.Held || !Snowmen.Contains(v.Friend)) v.Friend=FindYetiFriend(v);
                double tx=v.TargetX;
                double ty=VisitorGround(v.X);
                int chopFacing=1;
                if (v.Timber!=null) {
                    double reach=23*v.Scale;
                    chopFacing=v.Timber.X<reach ? -1 : v.Timber.X>width-reach ? 1 : v.Timber.X<v.X ? -1 : 1;
                    tx=v.Timber.X-chopFacing*reach;
                } else if (v.Friend!=null) {
                    tx=v.Friend.X-v.Friend.BaseRadius-8*v.Scale;
                    ty=v.Friend.Y;
                }
                double dx=tx-v.X,walk=Limit(dx,-42*pacedDt,42*pacedDt);
                v.Facing=dx<0?-1:1;v.X+=walk;v.Travel+=Math.Abs(walk);
                if(v.Friend==null || Math.Abs(v.Friend.Y-VisitorGround(v.Friend.X))<3)
                    v.Y=VisitorGround(v.X);
                else v.Y+=Limit(ty-v.Y,-62*pacedDt,62*pacedDt);
                if(Math.Abs(v.X-tx)<2 && Math.Abs(v.Y-ty)<3) {
                    v.Met=true;
                    if(v.Timber!=null) v.Facing=chopFacing;
                    else if(v.Friend!=null) {
                        v.Friend.Facing=v.X<v.Friend.X?-1:1;
                        PowderBurst(v.Friend.X,v.Friend.Y-v.Friend.Height*.6,12,0,.55);
                    }
                }
            } else if (v.Timber!=null) {
                // A moving player or plough can take the tree out of reach mid-swing.
                if (Math.Abs(v.Timber.X-v.X)>31*v.Scale) {v.Met=false;v.Wait=0;v.Chops=0;return false;}
                v.Wait+=dt;
                if (v.Wait>=(v.Chops+.72)*ChopBeat) {
                    v.Chops++;
                    PowderBurst(v.Timber.X,v.Timber.Y-8*v.Scale,5+v.Chops*2,45*v.Facing,.46);
                    if (v.Chops==3) {
                        RemoveTree(v.Timber);
                        v.Timber=null;v.CarryingLog=true;v.Wait=0;v.Dwell=.52;
                    }
                }
            } else if ((v.Wait+=dt)>v.Dwell) {
                v.Facing=1;v.X+=42*pacedDt;v.Travel+=42*pacedDt;
                v.Y+=Limit(VisitorGround(v.X)-v.Y,-62*pacedDt,62*pacedDt);
                if(v.X>width+55*v.Scale)return true;
            }
            return false;
        }
    }
}
